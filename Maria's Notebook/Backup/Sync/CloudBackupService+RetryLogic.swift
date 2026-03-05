// CloudBackupService+RetryLogic.swift
// Retry logic with exponential backoff for cloud backup operations

import Foundation
import SwiftData
import OSLog

extension CloudBackupService {

    // MARK: - Retry Logic with Exponential Backoff

    /// Executes an operation with automatic retry and exponential backoff.
    ///
    /// - Parameters:
    ///   - operation: The async operation to perform
    ///   - shouldRetry: Closure to determine if error is retryable (default: true for all errors)
    /// - Returns: The result of the operation
    public func withRetry<T>(
        operation: @escaping () async throws -> T,
        shouldRetry: @escaping (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?
        var delay = retryConfiguration.baseDelaySeconds

        for attempt in 0...retryConfiguration.maxRetries {
            currentRetryAttempt = attempt

            do {
                let result = try await operation()
                currentRetryAttempt = 0
                return result
            } catch {
                lastError = error

                // Check if we should retry
                if attempt < retryConfiguration.maxRetries && shouldRetry(error) {
                    // Wait with exponential backoff
                    let jitter = Double.random(in: 0...0.5)
                    let actualDelay = min(delay + jitter, retryConfiguration.maxDelaySeconds)

                    Logger.backup.error("Attempt \(attempt + 1) failed: \(error.localizedDescription). Retrying in \(actualDelay)s...")

                    try await Task.sleep(for: .seconds(actualDelay))
                    delay *= retryConfiguration.backoffMultiplier
                } else {
                    break
                }
            }
        }

        currentRetryAttempt = 0
        throw BackupOperationError.cloudOperationFailed(.uploadFailed(underlying: lastError!))
    }

    /// Exports a backup to iCloud with automatic retry on failure.
    public func exportToCloudWithRetry(
        modelContext: ModelContext,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> URL {
        try await withRetry {
            try await self.exportToCloud(
                modelContext: modelContext,
                password: password,
                progress: progress
            )
        } shouldRetry: { error in
            // Use the error's shouldRetry property if available
            if let backupError = error as? BackupOperationError {
                return backupError.shouldRetry
            }
            return true
        }
    }
}
