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
/// orphan to it. Automatic runs are triggered from four places:
///   1. Post-launch migrations (after the final viewContext save)
///   2. ClassroomSharingService when `isSharing` transitions `false → true`
///   3. DeduplicationCoordinator after each post-import dedup pass
///   4. SharedStoreOrphanGuard after any save that inserts a shared entity
///
/// Every automatic run first consults persistent history (see
/// `+HistoryGate`): when no shared entity has been inserted since the last
/// pass that left nothing to attach, the run costs one small history query
/// and reads no entity table at all. Only the manual "Repair Sync Errors"
/// button forces a full scan.
@Observable
final class SharedStoreZoneRepair {

    static let shared = SharedStoreZoneRepair()

    /// Not `private`: the `+Detection` extension lives in another file and
    /// Swift scopes `private` members to the declaring file.
    nonisolated static let logger = Logger.app(category: "SharedStoreZoneRepair")

    // MARK: - Observable State

    private(set) var orphanCount: Int = 0
    private(set) var orphansByEntity: [String: Int] = [:]
    private(set) var lastUnrecoverableOrphans: [NSManagedObjectID] = []
    private(set) var lastRunAt: Date?
    private(set) var repairInProgress: Bool = false
    private(set) var hasActiveShare: Bool = false

    /// The store's history token the last time this service looked. Lets the
    /// sharing screen's periodic recount return immediately when nothing has
    /// been written since — no history query, no entity fetch.
    private var lastObservedToken: NSPersistentHistoryToken?

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

    // MARK: - Public API

    /// Runs the detection-and-repair pass on the shared singleton.
    /// Idempotent and cheap when the shared store has no orphans.
    /// Respects the circuit breaker — for the manual "Repair Sync Errors"
    /// button, call `runManual` instead.
    static func runIfNeeded(coreDataStack: CoreDataStack) async {
        guard !isCircuitBreakerOpen else {
            shared.logger.notice("SharedStoreZoneRepair: circuit breaker open, skipping auto-run")
            return
        }
        guard !EnergyPolicy.shared.shouldDeferMaintenance else {
            shared.logger.notice("SharedStoreZoneRepair: device hot or in Low Power Mode, skipping auto-run")
            return
        }
        await shared.run(coreDataStack: coreDataStack)
    }

    /// User-initiated variant for the Settings → Repair Sync Errors
    /// button. Resets the circuit breaker so a subsequent timeout
    /// re-arms it, but otherwise behaves identically to `run`.
    func runManual(coreDataStack: CoreDataStack) async {
        Self.resetCircuitBreaker()
        await run(coreDataStack: coreDataStack, force: true)
    }

    /// Recounts records still waiting to move, without attaching anything.
    /// Called on every tick of the sharing screen, so it has to be nearly
    /// free when nothing is happening: it returns as soon as the store's
    /// history token matches the one it saw last, and otherwise asks history
    /// which entities (if any) gained rows before fetching anything. It
    /// distinguishes "nothing left" from "never checked" — `lastRunAt` stays
    /// nil until either a real pass or a clean history check has happened.
    func refreshCountsIfNeeded(coreDataStack: CoreDataStack) async {
        guard coreDataStack.isCloudKitActive,
              let store = coreDataStack.privatePersistentStore,
              !repairInProgress else { return }
        let container = coreDataStack.container
        let token = Self.currentHistoryToken(for: store, in: container)
        if let token, let seen = lastObservedToken, token == seen { return }

        let decision = await Self.gateDecision(since: Self.loadCleanToken(), container: container)
        guard let entityNames = Self.entityNamesToScan(for: decision) else {
            lastObservedToken = token
            if lastRunAt == nil { lastRunAt = Date() }
            return
        }
        await recount(entityNames: entityNames, store: store, container: container, token: token)
    }

    /// One counting pass over `entityNames`, recording a clean watermark when
    /// it finds nothing waiting.
    private func recount(
        entityNames: [String],
        store: NSPersistentStore,
        container: NSPersistentCloudKitContainer,
        token: NSPersistentHistoryToken?
    ) async {
        let scope = RepairScope(entityNames: entityNames, store: store, container: container)
        let report = await Self.collectOrphans(in: scope)
        guard !report.failed else { return }
        orphanCount = report.orphanIDs.count
        orphansByEntity = report.byEntity
        lastObservedToken = token
        if lastRunAt == nil { lastRunAt = Date() }
        if report.orphanIDs.isEmpty {
            markClean(token)
        }
    }

    /// The entities a pass should read for `decision`, or `nil` for "none".
    nonisolated static func entityNamesToScan(for decision: GateDecision) -> [String]? {
        switch decision {
        case .clean:
            return nil
        case let .scan(names):
            return names.sorted()
        case .scanEverything:
            return CoreDataStack.sharedEntityNames.sorted()
        }
    }

    /// The entity names an automatic pass should scan, or `nil` when history
    /// shows nothing shared was inserted since the last clean pass. `force`
    /// (the manual button) bypasses the gate and scans everything.
    private func scanScope(
        force: Bool,
        store: NSPersistentStore,
        container: NSPersistentCloudKitContainer,
        tokenBefore: NSPersistentHistoryToken?
    ) async -> [String]? {
        if force { return CoreDataStack.sharedEntityNames.sorted() }
        let decision = await Self.gateDecision(since: Self.loadCleanToken(), container: container)
        if case let .scanEverything(reason) = decision {
            Self.logger.notice("Zone repair pass scanning every shared entity: \(reason, privacy: .public)")
        }
        guard let entityNames = Self.entityNamesToScan(for: decision) else {
            // Nothing that could be an orphan exists. Keep the share flag
            // accurate on the first look of the session — the orphan guard
            // uses it to choose between repair and auto-create.
            if lastRunAt == nil {
                hasActiveShare = (try? container.fetchShares(in: store).first) != nil
            }
            lastObservedToken = tokenBefore
            lastRunAt = Date()
            Self.logger.debug("Zone repair pass skipped: no shared entity inserted since the last clean pass")
            return nil
        }
        return entityNames
    }

    /// Records `token` as the point up to which the private store is known to
    /// hold no orphans. Only ever called after a pass that found nothing left
    /// to attach — see `+HistoryGate` for why that is sufficient.
    private func markClean(_ token: NSPersistentHistoryToken?) {
        guard let token else { return }
        Self.saveCleanToken(token)
    }

    private var logger: Logger { Self.logger }

    /// Instance variant of `runIfNeeded`. Use the static form from call
    /// sites that don't need to bind to the singleton directly.
    ///
    /// - Parameter force: Skip the history gate and scan every shared entity.
    ///   Only the user's "Repair Sync Errors" button passes `true`.
    func run(coreDataStack: CoreDataStack, force: Bool = false) async {
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

        let container = coreDataStack.container

        // Captured before anything is read, so an insert that lands during
        // this pass is still ahead of the watermark it may record.
        let tokenBefore = Self.currentHistoryToken(for: store, in: container)

        guard let entityNames = await scanScope(
            force: force, store: store, container: container, tokenBefore: tokenBefore
        ) else { return }

        repairInProgress = true
        defer {
            repairInProgress = false
            lastRunAt = Date()
            lastObservedToken = tokenBefore
        }

        let scope = RepairScope(entityNames: entityNames, store: store, container: container)
        let report = await Self.collectOrphans(in: scope)

        guard !report.failed else {
            // CloudKit could not say which zone anything lives in. Leave the
            // counts and the watermark alone; the next trigger tries again.
            return
        }

        orphanCount = report.orphanIDs.count
        orphansByEntity = report.byEntity

        guard !report.orphanIDs.isEmpty else {
            lastUnrecoverableOrphans = []
            hasActiveShare = (try? container.fetchShares(in: store).first) != nil
            markClean(tokenBefore)
            Self.logger.notice("Zone repair pass: nothing to attach, 0 records waiting")
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
            await repairOrphans(report.orphanIDs, with: share, in: scope)
            if orphanCount == 0 && lastUnrecoverableOrphans.isEmpty {
                markClean(tokenBefore)
            }
        } else {
            reportOrphansWithoutShare(count: report.orphanIDs.count)
        }
    }

    /// Attaches `orphanIDs` to `share`, then refreshes the observable orphan
    /// counts from whatever survived the pass.
    private func repairOrphans(
        _ orphanIDs: [NSManagedObjectID],
        with share: CKShare,
        in scope: RepairScope
    ) async {
        lastUnrecoverableOrphans = await attachOrphans(
            orphanIDs,
            to: share,
            container: scope.container
        )

        let remaining = await Self.collectOrphans(in: scope)
        guard !remaining.failed else { return }
        orphanCount = remaining.orphanIDs.count
        orphansByEntity = remaining.byEntity
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
}
