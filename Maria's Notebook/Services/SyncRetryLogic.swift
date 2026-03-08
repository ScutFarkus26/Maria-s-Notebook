import Foundation
import OSLog

/// Service responsible for managing retry logic with exponential backoff
@Observable
@MainActor
final class SyncRetryLogic {
    private static let logger = Logger.sync

    // MARK: - State
    
    /// Current retry attempt count for failed syncs
    private(set) var retryAttempt: Int = 0
    
    /// Maximum number of retry attempts before giving up
    private let maxRetryAttempts: Int = 5
    
    /// Base delay for exponential backoff (in seconds)
    private let baseRetryDelay: Double = 2.0
    
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
    
    /// Cancel any pending retry operations
    func cancelRetry() {
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
            guard let self = self else { return }

            // Wait for the backoff delay
            do {
                try await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
            } catch {
                Self.logger.warning("Task sleep interrupted during retry: \(error.localizedDescription)")
                return
            }
            
            // Check if conditions are now favorable
            guard canRetry() else {
                // Still offline, schedule another retry
                self.scheduleRetry(
                    canRetry: canRetry,
                    syncAction: syncAction,
                    onMaxRetriesReached: onMaxRetriesReached
                )
                return
            }
            
            // Attempt sync
            let success = await syncAction()
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
