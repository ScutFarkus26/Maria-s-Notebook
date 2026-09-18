import Foundation
import CoreData
import OSLog

/// Coordinates post-sync deduplication with debouncing to prevent rapid-fire runs.
/// Triggered by CloudKit import events to clean up merge-conflict duplicates.
///
/// Two callers feed one debounced cycle. `PersistentHistoryProcessor` reports
/// which entities a remote batch inserted, and the pass is scoped to exactly
/// those (an empty report means nothing to sweep). `CloudKitSyncStatusService`
/// reports each successful import; on its own that is the safety net for an
/// import whose history could not be read and it sweeps everything, but beside
/// a history report it defers to the report's scope. A plain
/// `requestDeduplication()` always sweeps everything.
@Observable
final class DeduplicationCoordinator {
    static let shared = DeduplicationCoordinator()
    nonisolated private static let logger = Logger.app(category: "DeduplicationCoordinator")

    var persistentContainer: NSPersistentContainer?

    /// CoreDataStack reference used to run SharedStoreZoneRepair after
    /// each post-import dedup pass. Weak to avoid retain cycles —
    /// the stack owns this singleton's lifetime indirectly via AppDependencies.
    weak var coreDataStack: CoreDataStack?

    private var debounceTask: Task<Void, Never>?
    private var isRunning = false

    /// What the cycle now being debounced has been asked to read.
    private enum PendingScope {
        /// Only the import-event safety net has spoken (or nothing has).
        case unreported
        /// The history processor reported these inserted entities.
        case inserted(Set<String>)
        /// A plain request, or a report on top of one: sweep everything.
        case everything

        mutating func add(insertedEntities: Set<String>) {
            switch self {
            case .unreported: self = .inserted(insertedEntities)
            case let .inserted(names): self = .inserted(names.union(insertedEntities))
            case .everything: break
            }
        }

        var resolved: DeduplicationScope {
            switch self {
            case .unreported, .everything: return .everything
            case let .inserted(names): return DeduplicationScope(insertedEntities: names)
            }
        }
    }

    private var pendingScope: PendingScope = .unreported

    /// How long requests are coalesced before the pass runs. Fixed at 5 s in
    /// the app; the energy-gating tests shorten it so they don't sleep.
    private let debounceInterval: Duration

    /// A hot device or Low Power Mode re-arms the debounce instead of running,
    /// but only this many times in a row — after that a permanently warm
    /// device dedups anyway rather than never cleaning up merge conflicts.
    static let defaultMaxEnergyDeferrals = 12

    /// This coordinator's re-arm limit. Only the tests lower it, so they can
    /// watch the fall-through without waiting out a dozen debounce intervals.
    let maxEnergyDeferrals: Int

    /// Consecutive energy deferrals in the current debounce cycle. Resets when
    /// a pass is finally allowed to start.
    private(set) var energyDeferralCount = 0

    /// How many times the debounced pass has been allowed to start. Bumped
    /// even when there is no container to work on, so it measures the gate
    /// rather than the outcome.
    private(set) var runAttemptCount = 0

    /// The scope the most recent pass was allowed to start with.
    private(set) var lastRunScope: DeduplicationScope?

    private init() {
        self.debounceInterval = .seconds(5)
        self.maxEnergyDeferrals = Self.defaultMaxEnergyDeferrals
    }

    /// Test seam: an isolated coordinator with a short debounce.
    init(debounceInterval: Duration, maxEnergyDeferrals: Int = defaultMaxEnergyDeferrals) {
        self.debounceInterval = debounceInterval
        self.maxEnergyDeferrals = maxEnergyDeferrals
    }

    /// Request a debounced deduplication run over every entity.
    /// Multiple calls within 5 seconds are coalesced into a single run.
    ///
    /// Deduplication is discretionary maintenance, so a hot device or Low
    /// Power Mode re-arms the debounce instead of running (see
    /// `maxEnergyDeferrals`).
    func requestDeduplication(policy: EnergyPolicy = .shared) {
        pendingScope = .everything
        armDebounce(policy: policy)
    }

    /// The history processor's report: a remote batch inserted rows in these
    /// entities (possibly none). Reports within one cycle are unioned.
    func requestDeduplication(insertedEntities: Set<String>, policy: EnergyPolicy = .shared) {
        pendingScope.add(insertedEntities: insertedEntities)
        armDebounce(policy: policy)
    }

    /// A successful CloudKit import. Sweeps everything only when no history
    /// report arrives for the same cycle.
    func requestDeduplicationAfterImport(policy: EnergyPolicy = .shared) {
        armDebounce(policy: policy)
    }

    private func armDebounce(policy: EnergyPolicy) {
        debounceTask?.cancel()
        let interval = debounceInterval
        energyDeferralCount = 0
        debounceTask = Task { [weak self] in
            while true {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }

                guard policy.shouldDeferMaintenance,
                      self.energyDeferralCount < self.maxEnergyDeferrals else {
                    self.runDeduplication()
                    return
                }

                self.energyDeferralCount += 1
                let count = self.energyDeferralCount
                let limit = self.maxEnergyDeferrals
                Self.logger.notice(
                    "Deduplication deferred (device hot or in Low Power Mode), re-arm \(count)/\(limit)"
                )
            }
        }
    }

    private func runDeduplication() {
        runAttemptCount += 1
        let scope = pendingScope.resolved
        pendingScope = .unreported
        lastRunScope = scope
        guard !isRunning, let container = persistentContainer else { return }
        isRunning = true

        // Nothing was inserted, so there is nothing to read: skip the context
        // and the pass, but still make the zone-repair call every pass ends with.
        guard !scope.isEmpty else {
            Self.logger.debug("Post-import deduplication skipped: the import inserted nothing")
            finishRun()
            return
        }

        let bgContext = container.newBackgroundContext()
        bgContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        // CloudKit container for deterministic survivor selection — every device
        // must keep the same duplicate, or peers delete each other's survivors.
        let cloudKitContainer = container as? NSPersistentCloudKitContainer

        Task.detached(priority: .utility) { [weak self] in
            await bgContext.perform {
                let start = Date()
                let results = DataCleanupService.deduplicateAllModels(
                    using: bgContext, container: cloudKitContainer, scope: scope
                )

                if !results.isEmpty {
                    if bgContext.safeSave() {
                        Self.logger.info("Post-import deduplication removed \(results.values.reduce(0, +)) duplicates")
                    }
                }

                let elapsed: String = String(format: "%.2f", Date().timeIntervalSince(start))
                let scoped: String = Self.describe(scope)
                Self.logger.debug("Post-import deduplication (\(scoped, privacy: .public)) completed in \(elapsed)s")
            }

            await MainActor.run { [weak self] in
                self?.finishRun()
            }
        }
    }

    nonisolated private static func describe(_ scope: DeduplicationScope) -> String {
        guard let names = scope.entityNames else { return "every entity" }
        return "\(names.count) entities"
    }

    private func finishRun() {
        isRunning = false
        if let stack = coreDataStack {
            // `runIfNeeded` honors the 24-hour circuit breaker that exists
            // to stop repeated full-database zone scans (each of which can
            // sit on a 10-minute CloudKit lock wait). Every other automatic
            // call site uses it; this one bypassed it on every import.
            Task { await SharedStoreZoneRepair.runIfNeeded(coreDataStack: stack) }
        }
    }
}
