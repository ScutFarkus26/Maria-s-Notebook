import Foundation

/// Serial queue that runs story analyses one-at-a-time so we never have multiple
/// `LanguageModelSession`s competing on-device. Tracks a public count of jobs in
/// flight so the UI can show progress.
@Observable
final class StoryImportQueue {
    static let shared = StoryImportQueue()

    /// Total number of story analyses currently queued (running + waiting).
    private(set) var pendingCount: Int = 0
    /// Number of analyses already finished in the current batch.
    private(set) var completedInBatch: Int = 0
    /// Total size of the current batch (resets to 0 when the queue drains).
    private(set) var batchSize: Int = 0

    private let processor = StoryImportQueueProcessor()

    private init() {}

    /// Submits an analysis job. Jobs run serially in submission order.
    func submit(_ work: @escaping @Sendable () async -> Void) {
        pendingCount += 1
        batchSize += 1
        Task {
            await processor.run(work)
            self.markCompleted()
        }
    }

    private func markCompleted() {
        pendingCount = Swift.max(0, pendingCount - 1)
        completedInBatch += 1
        if pendingCount == 0 {
            completedInBatch = 0
            batchSize = 0
        }
    }
}

/// Actor that serializes execution of submitted closures: actor isolation guarantees
/// only one `run(_:)` call is in flight at a time.
private actor StoryImportQueueProcessor {
    func run(_ work: @Sendable () async -> Void) async {
        await work()
    }
}
