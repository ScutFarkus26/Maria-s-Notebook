import Foundation
import CoreData
import OSLog

/// Coordinates post-sync deduplication with debouncing to prevent rapid-fire runs.
/// Triggered by CloudKit import events to clean up merge-conflict duplicates.
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

    private init() {
        self.debounceInterval = .seconds(5)
        self.maxEnergyDeferrals = Self.defaultMaxEnergyDeferrals
    }

    /// Test seam: an isolated coordinator with a short debounce.
    init(debounceInterval: Duration, maxEnergyDeferrals: Int = defaultMaxEnergyDeferrals) {
        self.debounceInterval = debounceInterval
        self.maxEnergyDeferrals = maxEnergyDeferrals
    }

    /// Request a debounced deduplication run.
    /// Multiple calls within 5 seconds are coalesced into a single run.
    ///
    /// Deduplication is discretionary maintenance, so a hot device or Low
    /// Power Mode re-arms the debounce instead of running (see
    /// `maxEnergyDeferrals`).
    func requestDeduplication(policy: EnergyPolicy = .shared) {
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
        guard !isRunning, let container = persistentContainer else { return }
        isRunning = true

        let bgContext = container.newBackgroundContext()
        bgContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        // CloudKit container for deterministic survivor selection — every device
        // must keep the same duplicate, or peers delete each other's survivors.
        let cloudKitContainer = container as? NSPersistentCloudKitContainer

        Task.detached(priority: .utility) { [weak self] in
            await bgContext.perform {
                let start = Date()
                let results = DataCleanupService.deduplicateAllModels(using: bgContext, container: cloudKitContainer)

                if !results.isEmpty {
                    if bgContext.safeSave() {
                        Self.logger.info("Post-import deduplication removed \(results.values.reduce(0, +)) duplicates")
                    }
                }

                let elapsed = Date().timeIntervalSince(start)
                Self.logger.debug("Post-import deduplication completed in \(String(format: "%.2f", elapsed))s")
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isRunning = false
                if let stack = self.coreDataStack {
                    // `runIfNeeded` honors the 24-hour circuit breaker that exists
                    // to stop repeated full-database zone scans (each of which can
                    // sit on a 10-minute CloudKit lock wait). Every other automatic
                    // call site uses it; this one bypassed it on every import.
                    Task { await SharedStoreZoneRepair.runIfNeeded(coreDataStack: stack) }
                }
            }
        }
    }
}
