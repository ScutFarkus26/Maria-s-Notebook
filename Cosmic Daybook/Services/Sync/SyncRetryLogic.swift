import Foundation
import OSLog

/// Service responsible for managing retry logic with exponential backoff
@Observable
final class SyncRetryLogic {
    private static let logger = Logger.sync

    // MARK: - State
    
    /// How many retries of the current failure chain have run. A retry counts
    /// once it has run, not when it is scheduled: the failed events that
    /// arrive while one waits are the same failure, and used to spend an
    /// attempt each, so a burst of them ran the five out in seconds (bug hunt
    /// 2026-11-02, #4).
    private(set) var retryAttempt: Int = 0

    /// True once this chain's "keeps failing" was reported: it is said once
    /// per chain, and the chain ends only on `resetRetryCount` (a successful
    /// import or export, or Sync Now's clear). The network coming back starts
    /// the attempts again but not the report.
    private(set) var exhaustionReported = false
    
    /// Maximum number of retry attempts before giving up
    private let maxRetryAttempts: Int = 5
    
    /// Base delay for exponential backoff (in seconds)
    private let baseRetryDelay: Double

    /// `baseRetryDelay` is shorter only in tests.
    init(baseRetryDelay: Double = 2.0) {
        self.baseRetryDelay = baseRetryDelay
    }

    /// Task for retry operations
    private var retryTask: Task<Void, Never>?

    /// Public read-only max retry attempts for diagnostics UI.
    var maxRetryCount: Int { maxRetryAttempts }

    /// Whether a retry task is currently scheduled.
    var hasPendingRetry: Bool { retryTask != nil }
    
    // MARK: - Public API
    
    /// Reset the retry counter
    func resetRetryCount() {
        retryAttempt = 0
        exhaustionReported = false
        retryTask?.cancel()
        retryTask = nil
    }

    /// Schedules a retry with exponential backoff, once per failure: while a
    /// retry waits, further failed events add nothing (they are what it will
    /// retry). When the attempts are used up, `onMaxRetriesReached` is called
    /// once for the chain, not on every failed event after it.
    /// - Parameters:
    ///   - canRetry: Closure to check if retry conditions are met (network, iCloud, etc.)
    ///   - syncAction: Closure to perform the actual sync operation, returns success status
    ///   - onMaxRetriesReached: Closure called when max retries exceeded
    func scheduleRetry(
        canRetry: @escaping () -> Bool,
        syncAction: @escaping () async -> Bool,
        onMaxRetriesReached: @escaping () -> Void
    ) {
        guard retryTask == nil else { return }
        guard retryAttempt < maxRetryAttempts else {
            guard !exhaustionReported else { return }
            exhaustionReported = true
            onMaxRetriesReached()
            return
        }

        // Calculate delay with exponential backoff: 2s, 4s, 8s, 16s, 32s
        let delay = baseRetryDelay * pow(2.0, Double(retryAttempt))

        retryTask = Task { [weak self] in
            guard let self else { return }

            // Wait for the backoff delay. A cancel means a reset replaced
            // this one, and owns `retryTask` now.
            do {
                try await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            } catch {
                return
            }

            // Offline: this attempt never ran, so it isn't used up. Coming
            // back online runs the retry (`retryPendingSync`), so nothing is
            // scheduled meanwhile; offline waits used to spend all five.
            guard canRetry() else {
                Self.logger.debug("Sync retry waits for the network to come back")
                self.retryTask = nil
                return
            }

            self.retryAttempt += 1
            let success = await syncAction()
            guard !Task.isCancelled else { return }
            // Finished: "Trying again soon" ends here unless another retry follows.
            self.retryTask = nil
            // A save that failed is this attempt failing: try again, or say
            // the chain is spent. One that worked waits for iCloud's next
            // event, which either ends the chain or asks for the next retry.
            if !success {
                self.scheduleRetry(
                    canRetry: canRetry,
                    syncAction: syncAction,
                    onMaxRetriesReached: onMaxRetriesReached
                )
            }
        }
    }
    
    /// Called when network/iCloud is restored to trigger pending retries
    /// - Parameters:
    ///   - canRetry: Closure to check if retry conditions are met
    ///   - hasPendingWork: Closure to check if there's work to retry
    ///   - syncAction: Closure to perform the actual sync operation
    func retryPendingSync(
        canRetry: @escaping () -> Bool,
        hasPendingWork: @escaping () -> Bool,
        syncAction: @escaping () async -> Void
    ) {
        guard canRetry() else { return }
        guard hasPendingWork() else { return }
        
        // Reset retry count and try immediately
        retryAttempt = 0
        Task {
            await syncAction()
        }
    }
}
