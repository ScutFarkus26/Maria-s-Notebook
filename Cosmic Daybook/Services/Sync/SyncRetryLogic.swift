import Foundation
import OSLog

/// Service responsible for managing retry logic with exponential backoff
@Observable
final class SyncRetryLogic {
    private static let logger = Logger.sync

    // MARK: - State
    
    /// Current retry attempt count for failed syncs
    private(set) var retryAttempt: Int = 0
    
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
        retryTask?.cancel()
        retryTask = nil
    }

    /// Schedules a retry with exponential backoff
    /// - Parameters:
    ///   - canRetry: Closure to check if retry conditions are met (network, iCloud, etc.)
    ///   - syncAction: Closure to perform the actual sync operation, returns success status
    ///   - onMaxRetriesReached: Closure called when max retries exceeded
    func scheduleRetry(
        canRetry: @escaping () -> Bool,
        syncAction: @escaping () async -> Bool,
        onMaxRetriesReached: @escaping () -> Void
    ) {
        guard retryAttempt < maxRetryAttempts else {
            onMaxRetriesReached()
            return
        }
        
        retryTask?.cancel()
        
        // Calculate delay with exponential backoff: 2s, 4s, 8s, 16s, 32s
        let delay = baseRetryDelay * pow(2.0, Double(retryAttempt))
        retryAttempt += 1
        
        retryTask = Task { [weak self] in
            guard let self else { return }

            // Wait for the backoff delay. A cancel means a newer retry or a
            // reset replaced this one, and owns `retryTask` now.
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
                self.retryAttempt = max(0, self.retryAttempt - 1)
                self.retryTask = nil
                return
            }

            let success = await syncAction()
            guard !Task.isCancelled else { return }
            // Finished: "Trying again soon" ends here unless another retry follows.
            self.retryTask = nil
            if !success && self.retryAttempt < self.maxRetryAttempts {
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
