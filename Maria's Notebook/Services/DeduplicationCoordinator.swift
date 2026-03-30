import Foundation
import SwiftData
import OSLog

/// Coordinates post-sync deduplication with debouncing to prevent rapid-fire runs.
/// Triggered by CloudKit import events to clean up merge-conflict duplicates.
@Observable
@MainActor
final class DeduplicationCoordinator {
    static let shared = DeduplicationCoordinator()
    nonisolated private static let logger = Logger.app(category: "DeduplicationCoordinator")

    var modelContainer: ModelContainer?

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
            await self?.runDeduplication()
        }
    }

    private func runDeduplication() {
        guard !isRunning, let container = modelContainer else { return }
        isRunning = true

        Task.detached(priority: .utility) { [weak self] in
            let context = ModelContext(container)
            context.autosaveEnabled = false

            let start = Date()
            let results = DataCleanupService.deduplicateAllModels(using: context)

            if !results.isEmpty {
                do {
                    try context.save()
                    Self.logger.info("Post-import deduplication removed \(results.values.reduce(0, +)) duplicates")
                } catch {
                    Self.logger.error("Post-import deduplication save failed: \(error.localizedDescription)")
                }
            }

            let elapsed = Date().timeIntervalSince(start)
            Self.logger.debug("Post-import deduplication completed in \(String(format: "%.2f", elapsed))s")

            await MainActor.run { [weak self] in
                self?.isRunning = false
            }
        }
    }
}
