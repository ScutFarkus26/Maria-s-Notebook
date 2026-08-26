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

    /// Not `private`: the `+Detection` extension lives in another file and
    /// Swift scopes `private` members to the declaring file.
    static let logger = Logger.app(category: "SharedStoreZoneRepair")

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

        // Once NSPersistentCloudKitContainer's mirroring delegate has died,
        // every `container.share(_:to:)` call fails — and it reports that
        // failure by *raising* an Objective-C exception from inside its own
        // fault-firing, which no Swift `catch` can trap (see `shareOffMain`).
        // There is no recovery short of a relaunch with clean local state, so
        // stop before we reach the uncatchable call.
        guard !CloudKitSyncStatusService.shared.mirroringDelegateFailed else {
            let deadMsg = "SharedStoreZoneRepair: CloudKit mirroring delegate failed this session, " +
                "skipping repair — relaunch (or Settings → Database → Reset Local Cache) is required"
            Self.logger.warning("\(deadMsg, privacy: .public)")
            return
        }

        repairInProgress = true
        defer {
            repairInProgress = false
            lastRunAt = Date()
        }

        let scope = RepairScope(
            entityNames: CoreDataStack.sharedEntityNames.sorted(),
            store: store,
            context: coreDataStack.viewContext,
            container: coreDataStack.container
        )
        let container = scope.container

        let (orphans, perEntity) = collectOrphans(in: scope)

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
            await repairOrphans(orphans, with: share, in: scope)
        } else {
            reportOrphansWithoutShare(count: orphans.count)
        }
    }

    /// Attaches `orphans` to `share`, then refreshes the observable orphan
    /// counts from whatever survived the pass.
    private func repairOrphans(
        _ orphans: [NSManagedObject],
        with share: CKShare,
        in scope: RepairScope
    ) async {
        lastUnrecoverableOrphans = await attachOrphans(
            orphans,
            to: share,
            container: scope.container
        )

        let (remaining, remainingByEntity) = collectOrphans(in: scope)
        orphanCount = remaining.count
        orphansByEntity = remainingByEntity
    }

    /// The safe-by-default case: orphans exist but there is no CKShare to
    /// attach them to, so this only reports — it never creates a share or
    /// deletes user data.
    private func reportOrphansWithoutShare(count: Int) {
        lastUnrecoverableOrphans = []
        let msg = "Private store has \(count) classroom record(s) outside any CKShare " +
            "zone, but no CKShare exists yet. CloudKit export will fail until the lead " +
            "guide runs Settings → Classroom Sharing → Share Classroom."
        Self.logger.warning("\(msg, privacy: .public)")
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
        let attachMsg = "Attaching \(orphanIDs.count) orphan record(s) in chunks of \(chunkSize)"
        Self.logger.info("\(attachMsg, privacy: .public)")

        var failures: [NSManagedObjectID] = []
        var successCount = 0
        let chunkCount = (orphanIDs.count + chunkSize - 1) / chunkSize

        for (chunkIndex, start) in stride(from: 0, to: orphanIDs.count, by: chunkSize).enumerated() {
            let end = min(start + chunkSize, orphanIDs.count)
            let chunkIDs = Array(orphanIDs[start..<end])

            do {
                try await Self.shareOffMain(chunkIDs: chunkIDs, share: share, container: container)
                successCount += chunkIDs.count
                let chunkMsg = "Chunk \(chunkIndex + 1)/\(chunkCount): attached \(chunkIDs.count)" +
                    " record(s) (running total: \(successCount)/\(orphanIDs.count))"
                Self.logger.info("\(chunkMsg, privacy: .public)")
                await Task.yield()
                continue
            } catch {
                let ns = error as NSError
                let failMsg = "Chunk \(chunkIndex + 1)/\(chunkCount) batch attach failed: " +
                    "domain=\(ns.domain) code=\(ns.code) description=\(ns.localizedDescription)" +
                    " userInfo=\(ns.userInfo)."
                Self.logger.warning("\(failMsg, privacy: .public)")

                if let reason = abortReason(for: ns) {
                    failures.append(contentsOf: orphanIDs[start..<orphanIDs.count])
                    let abortMsg = "Orphan attachment aborted (\(reason)): \(successCount) succeeded, " +
                        "\(failures.count) deferred"
                    Self.logger.error("\(abortMsg, privacy: .public)")
                    return failures
                }
            }

            // The whole-chunk call failed for a reason that might be specific
            // to one bad record, so retry the chunk one record at a time.
            let fallback = await attachIndividually(chunkIDs, to: share, container: container)
            successCount += fallback.succeeded
            failures.append(contentsOf: fallback.failures)

            if fallback.delegateDied {
                failures.append(contentsOf: fallback.untried)
                failures.append(contentsOf: orphanIDs[end..<orphanIDs.count])
                let abortMsg = "Orphan attachment aborted (mirroring delegate dead): " +
                    "\(successCount) succeeded, \(failures.count) deferred"
                Self.logger.error("\(abortMsg, privacy: .public)")
                return failures
            }

            // Yield between chunks so we don't monopolise the MainActor for
            // minutes and so any cancellation has a chance to propagate.
            await Task.yield()
        }

        let completeMsg = "Orphan attachment complete: \(successCount) succeeded, \(failures.count) unrecoverable"
        Self.logger.info("\(completeMsg, privacy: .public)")
        return failures
    }

    /// Why a whole-chunk failure should abandon the entire pass rather than
    /// fall back to per-record retries, or `nil` when per-record is worth a go.
    ///
    /// Both cases here fail identically for every remaining record, so retrying
    /// them one at a time buys nothing — and in the dead-delegate case the
    /// retries are what eventually walk into `container.share`'s uncatchable
    /// Objective-C exception (see `shareOffMain`).
    ///
    /// Returning a reason also arms the matching kill switch, because both
    /// conditions outlive this pass: the session-wide mirroring-delegate flag
    /// (cleared only by relaunching) or the 24-hour circuit breaker.
    private func abortReason(for error: NSError) -> String? {
        if Self.indicatesDeadMirroringDelegate(error) {
            CloudKitSyncStatusService.shared.mirroringDelegateFailed = true
            return "mirroring delegate never initialized, code \(error.code)"
        }

        // CloudKit's Share-Export timeout. Trip the circuit breaker so we don't
        // burn another ten-minute ulock wait per remaining record; the user can
        // retry from Settings → Repair Sync Errors.
        if error.domain == NSCocoaErrorDomain && error.code == 134060 {
            Self.trippedCircuitBreaker()
            return "Share-Export timed out, manual Repair required"
        }

        return nil
    }

    /// Per-record retry for one chunk, isolating a single pathological record
    /// instead of losing the whole chunk to it.
    private func attachIndividually(
        _ chunkIDs: [NSManagedObjectID],
        to share: CKShare,
        container: NSPersistentCloudKitContainer
    ) async -> ChunkFallbackResult {
        var result = ChunkFallbackResult()

        for (index, orphanID) in chunkIDs.enumerated() {
            do {
                try await Self.shareOffMain(chunkIDs: [orphanID], share: share, container: container)
                result.succeeded += 1
            } catch {
                result.failures.append(orphanID)
                let ns = error as NSError
                let uri = orphanID.uriRepresentation().absoluteString
                let errMsg = "Per-record attach failed for \(uri): " +
                    "domain=\(ns.domain) code=\(ns.code)" +
                    " description=\(ns.localizedDescription) userInfo=\(ns.userInfo)"
                Self.logger.error("\(errMsg, privacy: .public)")

                if Self.indicatesDeadMirroringDelegate(ns) {
                    CloudKitSyncStatusService.shared.mirroringDelegateFailed = true
                    result.delegateDied = true
                    result.untried = Array(chunkIDs[(index + 1)...])
                    return result
                }
            }
        }

        return result
    }

    /// Tally from one chunk's per-record retry pass.
    private struct ChunkFallbackResult {
        var succeeded = 0
        /// Records that were attempted and failed.
        var failures: [NSManagedObjectID] = []
        /// Records skipped because the pass aborted. Only ever non-empty when
        /// ``delegateDied`` is true.
        var untried: [NSManagedObjectID] = []
        /// True when the mirroring delegate died mid-chunk, meaning no further
        /// `container.share` call can succeed this session.
        var delegateDied = false
    }
}
