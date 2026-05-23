import Foundation
import CoreData
import CloudKit
import OSLog

/// Repairs records in the shared store that are not associated with any
/// CKShare zone. An orphan in the shared store cannot be exported to
/// CloudKit and poisons the mirroring delegate ("Failed to assign an
/// object to a record zone … must be assigned to a zone using
/// shareManagedObjects:toShare:completion:"), which then blocks every
/// subsequent import/export until the next launch.
///
/// Safe-by-default: when no CKShare exists in the shared store, this
/// service only logs the orphan count — it never auto-creates a share
/// or deletes user data.
///
/// When a CKShare does exist, the service attaches every detected
/// orphan to it. Re-runs are cheap when the shared store has no orphans
/// and are triggered from three places:
///   1. Post-launch migrations (after the final viewContext save)
///   2. ClassroomSharingService when `isSharing` transitions `false → true`
///   3. DeduplicationCoordinator after each post-import dedup pass
@Observable
@MainActor
final class SharedStoreZoneRepair {

    static let shared = SharedStoreZoneRepair()

    private static let logger = Logger.app(category: "SharedStoreZoneRepair")

    // MARK: - Observable State

    private(set) var orphanCount: Int = 0
    private(set) var orphansByEntity: [String: Int] = [:]
    private(set) var lastUnrecoverableOrphans: [NSManagedObjectID] = []
    private(set) var lastRunAt: Date?
    private(set) var repairInProgress: Bool = false
    private(set) var hasActiveShare: Bool = false

    private init() {}

    // MARK: - Circuit breaker

    /// UserDefaults key holding the timestamp of the most recent
    /// CloudKit timeout. While the timeout is within `circuitBreakerWindow`
    /// of now, automatic (non-user-initiated) repair runs are skipped.
    nonisolated private static let lastTimeoutKey = UserDefaultsKeys.sharedStoreZoneRepairLastTimeoutAt
    nonisolated private static let circuitBreakerWindow: TimeInterval = 24 * 60 * 60 // 24h

    /// True if a previous repair attempt timed out recently enough that
    /// auto-invocations should skip. Manual runs (the "Repair Sync
    /// Errors" button) bypass this check.
    static var isCircuitBreakerOpen: Bool {
        guard let last = UserDefaults.standard.object(forKey: lastTimeoutKey) as? Date else {
            return false
        }
        return Date().timeIntervalSince(last) < circuitBreakerWindow
    }

    static func resetCircuitBreaker() {
        UserDefaults.standard.removeObject(forKey: lastTimeoutKey)
    }

    /// Trips the circuit breaker. Call after a `container.share`/`fetchShares`
    /// timeout (NSCocoaErrorDomain 134060) so auto-paths defer for the next
    /// 24 hours.
    nonisolated static func tripCircuitBreakerOnTimeout() {
        UserDefaults.standard.set(Date(), forKey: lastTimeoutKey)
    }

    private static func trippedCircuitBreaker() {
        Self.tripCircuitBreakerOnTimeout()
    }

    // MARK: - Public API

    /// Runs the detection-and-repair pass on the shared singleton.
    /// Idempotent and cheap when the shared store has no orphans.
    /// Respects the circuit breaker — for the manual "Repair Sync Errors"
    /// button, call `runManual` instead.
    static func runIfNeeded(coreDataStack: CoreDataStack) async {
        guard !isCircuitBreakerOpen else {
            shared.logger.info("SharedStoreZoneRepair: circuit breaker open, skipping auto-run")
            return
        }
        await shared.run(coreDataStack: coreDataStack)
    }

    /// User-initiated variant for the Settings → Repair Sync Errors
    /// button. Resets the circuit breaker so a subsequent timeout
    /// re-arms it, but otherwise behaves identically to `run`.
    func runManual(coreDataStack: CoreDataStack) async {
        Self.resetCircuitBreaker()
        await run(coreDataStack: coreDataStack)
    }

    private var logger: Logger { Self.logger }

    /// Instance variant of `runIfNeeded`. Use the static form from call
    /// sites that don't need to bind to the singleton directly.
    func run(coreDataStack: CoreDataStack) async {
        guard coreDataStack.isCloudKitActive else { return }
        // Post-refactor: lead-guide-owned classroom data lives in the
        // .private store. Detect and repair orphans there (matches where the
        // CKShare itself will live). The assistant device's accepted-share
        // data lives in the shared store, but accepted records are managed
        // by CloudKit and aren't "orphans" — so private is the right target
        // on both roles.
        guard let store = coreDataStack.privatePersistentStore else { return }
        guard !repairInProgress else { return }

        repairInProgress = true
        defer {
            repairInProgress = false
            lastRunAt = Date()
        }

        let entityNames = CoreDataStack.sharedEntityNames.sorted()
        let context = coreDataStack.viewContext
        let container = coreDataStack.container

        let (orphans, perEntity) = collectOrphans(
            entityNames: entityNames,
            in: store,
            context: context,
            container: container
        )

        orphanCount = orphans.count
        orphansByEntity = perEntity

        guard !orphans.isEmpty else {
            lastUnrecoverableOrphans = []
            hasActiveShare = (try? container.fetchShares(in: store).first) != nil
            return
        }

        let existingShare: CKShare?
        do {
            existingShare = try container.fetchShares(in: store).first
        } catch {
            Self.logger.error("Cannot inspect shares in shared store: \(error.localizedDescription, privacy: .public)")
            return
        }

        hasActiveShare = (existingShare != nil)

        if let share = existingShare {
            let unrecoverable = await attachOrphans(orphans, to: share, container: container)
            lastUnrecoverableOrphans = unrecoverable

            // Refresh the orphan picture after the repair pass so the
            // observable state reflects what remains stuck.
            let (remaining, remainingByEntity) = collectOrphans(
                entityNames: entityNames,
                in: store,
                context: context,
                container: container
            )
            orphanCount = remaining.count
            orphansByEntity = remainingByEntity
        } else {
            lastUnrecoverableOrphans = []
            let count = orphans.count
            Self.logger.warning("Private store has \(count, privacy: .public) classroom record(s) outside any CKShare zone, but no CKShare exists yet. CloudKit export will fail until the lead guide runs Settings → Classroom Sharing → Share Classroom.")
        }
    }

    // MARK: - Detection

    private func collectOrphans(
        entityNames: [String],
        in store: NSPersistentStore,
        context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer
    ) -> (orphans: [NSManagedObject], byEntity: [String: Int]) {
        var allObjectIDs: [NSManagedObjectID] = []
        var objectsByID: [NSManagedObjectID: NSManagedObject] = [:]
        var entityByID: [NSManagedObjectID: String] = [:]

        for entityName in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.affectedStores = [store]
            request.returnsObjectsAsFaults = true
            do {
                let objects = try context.fetch(request)
                for obj in objects {
                    allObjectIDs.append(obj.objectID)
                    objectsByID[obj.objectID] = obj
                    entityByID[obj.objectID] = entityName
                }
            } catch {
                let detail = error.localizedDescription
                Self.logger.warning("Failed to fetch \(entityName, privacy: .public) for zone check: \(detail, privacy: .public)")
            }
        }

        guard !allObjectIDs.isEmpty else { return ([], [:]) }

        let inShare: [NSManagedObjectID: CKShare]
        do {
            inShare = try container.fetchShares(matching: allObjectIDs)
        } catch {
            Self.logger.error("fetchShares(matching:) failed: \(error.localizedDescription, privacy: .public)")
            return ([], [:])
        }

        var orphans: [NSManagedObject] = []
        var byEntity: [String: Int] = [:]
        for id in allObjectIDs where inShare[id] == nil {
            if let obj = objectsByID[id] {
                orphans.append(obj)
                let name = entityByID[id] ?? "Unknown"
                byEntity[name, default: 0] += 1
            }
        }
        return (orphans, byEntity)
    }

    // MARK: - Attachment

    /// Attaches orphans to the share in **chunks**. NSPersistentCloudKitContainer's
    /// `Share-Export` task has an internal timeout, and attempting to attach
    /// thousands of records in one batch reliably trips it ("Share-Export
    /// timed out"). Chunking keeps each request small enough that the export
    /// scheduler finishes within its budget; per-chunk per-record fallback
    /// still isolates pathological records.
    ///
    /// `container.share(_:to:)` is documented as `async` but its implementation
    /// blocks the calling thread on a kernel `__ulock_wait` until CloudKit's
    /// internal Share-Export task resolves. To keep the MainActor responsive
    /// we marshal each share call through a `Task.detached` running against a
    /// background context — the ulock then blocks a cooperative-pool worker
    /// instead of the MainActor's runloop.
    ///
    /// We yield to the actor between chunks so the bootstrapper can interleave
    /// other work, and log progress so a multi-minute attach is visible in
    /// Console.
    private func attachOrphans(
        _ orphans: [NSManagedObject],
        to share: CKShare,
        container: NSPersistentCloudKitContainer
    ) async -> [NSManagedObjectID] {
        let chunkSize = 200
        let orphanIDs = orphans.map(\.objectID)
        Self.logger.info("Attaching \(orphanIDs.count, privacy: .public) orphan record(s) in chunks of \(chunkSize, privacy: .public)")

        var failures: [NSManagedObjectID] = []
        var successCount = 0
        let chunkCount = (orphanIDs.count + chunkSize - 1) / chunkSize

        for (chunkIndex, start) in stride(from: 0, to: orphanIDs.count, by: chunkSize).enumerated() {
            let end = min(start + chunkSize, orphanIDs.count)
            let chunkIDs = Array(orphanIDs[start..<end])

            do {
                try await Self.shareOffMain(chunkIDs: chunkIDs, share: share, container: container)
                successCount += chunkIDs.count
                Self.logger.info("Chunk \(chunkIndex + 1, privacy: .public)/\(chunkCount, privacy: .public): attached \(chunkIDs.count, privacy: .public) record(s) (running total: \(successCount, privacy: .public)/\(orphanIDs.count, privacy: .public))")
            } catch {
                let ns = error as NSError
                Self.logger.warning("Chunk \(chunkIndex + 1, privacy: .public)/\(chunkCount, privacy: .public) batch attach failed: domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public) description=\(ns.localizedDescription, privacy: .public) userInfo=\(ns.userInfo, privacy: .public). Falling back to per-record for this chunk.")

                // If the failure looks like CloudKit's 10-minute Share-Export
                // timeout (134060 with no specific in-store cross-store user
                // info), trip the circuit breaker and stop trying so we
                // don't burn another 10-minute ulock wait per remaining
                // record. The user can retry via the Repair button.
                if ns.domain == "NSCocoaErrorDomain" && ns.code == 134060 {
                    Self.logger.error("SharedStoreZoneRepair: tripping circuit breaker after Share-Export timeout — manual Repair will be required")
                    Self.trippedCircuitBreaker()
                    // Mark remaining records as failures and exit early.
                    let remaining = Array(orphanIDs[start..<orphanIDs.count])
                    failures.append(contentsOf: remaining)
                    Self.logger.info("Orphan attachment aborted: \(successCount, privacy: .public) succeeded, \(failures.count, privacy: .public) deferred (circuit breaker)")
                    return failures
                }

                for orphanID in chunkIDs {
                    do {
                        try await Self.shareOffMain(chunkIDs: [orphanID], share: share, container: container)
                        successCount += 1
                    } catch {
                        failures.append(orphanID)
                        let uri = orphanID.uriRepresentation().absoluteString
                        let pns = error as NSError
                        Self.logger.error("Per-record attach failed for \(uri, privacy: .public): domain=\(pns.domain, privacy: .public) code=\(pns.code, privacy: .public) description=\(pns.localizedDescription, privacy: .public) userInfo=\(pns.userInfo, privacy: .public)")
                    }
                }
            }

            // Yield between chunks so we don't monopolise the MainActor for
            // minutes and so any cancellation has a chance to propagate.
            await Task.yield()
        }

        Self.logger.info("Orphan attachment complete: \(successCount, privacy: .public) succeeded, \(failures.count, privacy: .public) unrecoverable")
        return failures
    }

    /// Runs `container.share(_:to:)` on a background context off the MainActor.
    /// The blocking ulock wait happens on a cooperative-pool worker, leaving
    /// the MainActor free to service view fetches and user input.
    ///
    /// `nonisolated` because we explicitly want this to run off MainActor.
    /// NSManagedObjectIDs are documented as thread-safe; the resolved
    /// NSManagedObjects only exist within the `performAndWait` block and the
    /// subsequent `container.share` await, both of which are bound to the
    /// freshly-created background context.
    private nonisolated static func shareOffMain(
        chunkIDs: [NSManagedObjectID],
        share: CKShare,
        container: NSPersistentCloudKitContainer
    ) async throws {
        try await Task.detached {
            let bg = container.newBackgroundContext()
            let objects: [NSManagedObject] = bg.performAndWait {
                chunkIDs.compactMap { bg.object(with: $0) }
            }
            _ = try await container.share(objects, to: share)
        }.value
    }

    /// Creates a new CKShare seeded from `seedID` off the MainActor. Mirrors
    /// `shareOffMain` for the orphan-attach path; used by
    /// `ClassroomSharingService` to keep its share-create flow from
    /// monopolising the main thread on the same kernel `ulock` as the attach
    /// path.
    ///
    /// Returns the newly-created CKShare on success.
    nonisolated static func createShareOffMain(
        seedID: NSManagedObjectID,
        container: NSPersistentCloudKitContainer
    ) async throws -> CKShare {
        try await Task.detached {
            let bg = container.newBackgroundContext()
            let seed: NSManagedObject? = bg.performAndWait {
                bg.object(with: seedID)
            }
            guard let seed else {
                throw NSError(
                    domain: "SharedStoreZoneRepair",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Seed record not available on background context"]
                )
            }
            let (_, share, _) = try await container.share([seed], to: nil)
            return share
        }.value
    }
}
