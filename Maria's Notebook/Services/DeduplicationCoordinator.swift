import Foundation
import CoreData
import OSLog

/// Coordinates post-sync deduplication with debouncing to prevent rapid-fire runs.
/// Triggered by CloudKit import events to clean up merge-conflict duplicates.
@Observable
@MainActor
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

    private init() {}

    /// Request a debounced deduplication run.
    /// Multiple calls within 5 seconds are coalesced into a single run.
    func requestDeduplication() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.runDeduplication()
        }
    }

    private func runDeduplication() {
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
                    do {
                        try bgContext.save()
                        Self.logger.info("Post-import deduplication removed \(results.values.reduce(0, +)) duplicates")
                    } catch {
                        Self.logger.error("Post-import deduplication save failed: \(error.localizedDescription)")
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
