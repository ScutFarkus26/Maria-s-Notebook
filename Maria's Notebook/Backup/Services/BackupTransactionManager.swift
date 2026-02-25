// BackupTransactionManager.swift
// Handles transaction rollback for failed imports and pre-import safety backups

import Foundation
import SwiftData
import OSLog

/// Manages backup transactions with rollback capability.
/// Creates safety checkpoints before destructive operations and provides
/// automatic recovery on failure.
@MainActor
public final class BackupTransactionManager {
    private static let logger = Logger.backup

    // MARK: - Types

    public enum TransactionError: LocalizedError {
        case checkpointCreationFailed(Error)
        case rollbackFailed(Error)
        case noCheckpointExists
        case importFailed(Error, checkpointURL: URL?)

        public var errorDescription: String? {
            switch self {
            case .checkpointCreationFailed(let error):
                return "Failed to create safety checkpoint: \(error.localizedDescription)"
            case .rollbackFailed(let error):
                return "Rollback failed: \(error.localizedDescription)"
            case .noCheckpointExists:
                return "No checkpoint exists for rollback."
            case .importFailed(let error, let checkpointURL):
                if let url = checkpointURL {
                    return "Import failed: \(error.localizedDescription). A safety backup was created at \(url.lastPathComponent)."
                }
                return "Import failed: \(error.localizedDescription)"
            }
        }
    }

    public struct TransactionResult {
        public let success: Bool
        public let checkpointURL: URL?
        public let rollbackPerformed: Bool
        public let error: Error?
    }

    // MARK: - Properties

    private let backupService: BackupService
    private let codec = BackupCodec()
    
    // MARK: - Initialization
    
    public init(backupService: BackupService) {
        self.backupService = backupService
    }

    /// Directory for storing transaction checkpoints
    private var checkpointDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups")
            .appendingPathComponent("Checkpoints")
    }

    /// Current active checkpoint URL
    private var activeCheckpointURL: URL?

    // MARK: - Public API

    /// Creates a safety checkpoint before a destructive operation.
    /// This backup can be used to restore the database if the operation fails.
    ///
    /// - Parameters:
    ///   - modelContext: The model context to backup
    ///   - operationName: Name of the operation (for filename)
    ///   - progress: Optional progress callback
    /// - Returns: URL of the checkpoint file
    public func createCheckpoint(
        modelContext: ModelContext,
        operationName: String,
        progress: BackupService.ProgressCallback? = nil
    ) async throws -> URL {
        // Ensure checkpoint directory exists
        try FileManager.default.createDirectory(
            at: checkpointDirectory,
            withIntermediateDirectories: true
        )

        // Create timestamped filename
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let sanitizedName = operationName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let filename = "Checkpoint-\(sanitizedName)-\(timestamp).\(BackupFile.fileExtension)"
        let checkpointURL = checkpointDirectory.appendingPathComponent(filename)

        do {
            _ = try await backupService.exportBackup(
                modelContext: modelContext,
                to: checkpointURL,
                password: nil,
                progress: progress ?? { _, _ in }
            )

            activeCheckpointURL = checkpointURL
            return checkpointURL
        } catch {
            throw TransactionError.checkpointCreationFailed(error)
        }
    }

    /// Executes an import operation with automatic rollback on failure.
    ///
    /// - Parameters:
    ///   - modelContext: The model context to import into
    ///   - backupURL: The backup file to import
    ///   - mode: The restore mode (merge or replace)
    ///   - password: Optional decryption password
    ///   - createCheckpoint: Whether to create a checkpoint before import (default: true for replace mode)
    ///   - progress: Progress callback
    /// - Returns: Transaction result with import summary or error details
    public func executeImportWithRollback(
        modelContext: ModelContext,
        from backupURL: URL,
        mode: BackupService.RestoreMode,
        password: String? = nil,
        shouldCreateCheckpoint createCheckpointOption: Bool? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {

        // Determine if we should create a checkpoint
        let shouldCreateCheckpoint = createCheckpointOption ?? (mode == .replace)

        var checkpointURL: URL?

        // Create checkpoint if needed
        if shouldCreateCheckpoint {
            progress(0.0, "Creating safety checkpoint…")
            do {
                checkpointURL = try await self.createCheckpoint(
                    modelContext: modelContext,
                    operationName: "PreImport",
                    progress: { subProgress, message in
                        // Scale checkpoint progress to 0-15%
                        progress(subProgress * 0.15, message)
                    }
                )
            } catch {
                // If checkpoint fails, we still allow the import to proceed
                // but warn the user
                Logger.backup.error("Checkpoint creation failed: \(error)")
            }
        }

        // Perform import
        progress(0.15, "Starting import…")
        do {
            let summary = try await backupService.importBackup(
                modelContext: modelContext,
                from: backupURL,
                mode: mode,
                password: password,
                progress: { subProgress, message in
                    // Scale import progress to 15-95%
                    progress(0.15 + (subProgress * 0.80), message)
                }
            )

            // Success - clean up checkpoint
            progress(0.95, "Cleaning up…")
            if let checkpointURL = checkpointURL {
                cleanupCheckpoint(at: checkpointURL)
            }
            activeCheckpointURL = nil

            progress(1.0, "Import complete")
            return summary

        } catch {
            // Import failed - attempt rollback if we have a checkpoint
            if let checkpointURL = checkpointURL {
                progress(0.96, "Import failed. Attempting rollback…")

                do {
                    try await rollback(
                        modelContext: modelContext,
                        from: checkpointURL,
                        progress: { subProgress, message in
                            progress(0.96 + (subProgress * 0.04), "Rollback: \(message)")
                        }
                    )

                    // Rollback successful - throw error with checkpoint info
                    throw TransactionError.importFailed(error, checkpointURL: checkpointURL)

                } catch let rollbackError as TransactionError {
                    throw rollbackError
                } catch {
                    // Rollback also failed
                    throw TransactionError.rollbackFailed(error)
                }
            } else {
                // No checkpoint available
                throw TransactionError.importFailed(error, checkpointURL: nil)
            }
        }
    }

    /// Manually rolls back to a checkpoint.
    ///
    /// - Parameters:
    ///   - modelContext: The model context to restore
    ///   - checkpointURL: The checkpoint file to restore from
    ///   - progress: Progress callback
    public func rollback(
        modelContext: ModelContext,
        from checkpointURL: URL,
        progress: @escaping BackupService.ProgressCallback
    ) async throws {
        guard FileManager.default.fileExists(atPath: checkpointURL.path) else {
            throw TransactionError.noCheckpointExists
        }

        do {
            _ = try await backupService.importBackup(
                modelContext: modelContext,
                from: checkpointURL,
                mode: .replace,
                password: nil,
                progress: progress
            )
        } catch {
            throw TransactionError.rollbackFailed(error)
        }
    }

    /// Rolls back to the most recent active checkpoint.
    ///
    /// - Parameters:
    ///   - modelContext: The model context to restore
    ///   - progress: Progress callback
    public func rollbackToActiveCheckpoint(
        modelContext: ModelContext,
        progress: @escaping BackupService.ProgressCallback
    ) async throws {
        guard let checkpointURL = activeCheckpointURL else {
            throw TransactionError.noCheckpointExists
        }

        try await rollback(
            modelContext: modelContext,
            from: checkpointURL,
            progress: progress
        )
    }

    /// Lists all available checkpoints.
    ///
    /// - Returns: Array of checkpoint URLs sorted by date (newest first)
    public func listCheckpoints() -> [URL] {
        guard FileManager.default.fileExists(atPath: checkpointDirectory.path) else {
            return []
        }

        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: checkpointDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            Self.logger.warning("Failed to list checkpoint directory: \(error)")
            return []
        }

        return files
            .filter { $0.pathExtension == BackupFile.fileExtension }
            .sorted { url1, url2 in
                let date1: Date
                let date2: Date
                do {
                    date1 = try url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                } catch {
                    Self.logger.warning("Failed to get creation date for \(url1.lastPathComponent): \(error)")
                    date1 = Date.distantPast
                }
                do {
                    date2 = try url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
                } catch {
                    Self.logger.warning("Failed to get creation date for \(url2.lastPathComponent): \(error)")
                    date2 = Date.distantPast
                }
                return date1 > date2
            }
    }

    /// Cleans up old checkpoints, keeping only the most recent ones.
    ///
    /// - Parameter keepCount: Number of checkpoints to keep (default: 3)
    public func cleanupOldCheckpoints(keepCount: Int = 3) {
        let checkpoints = listCheckpoints()

        if checkpoints.count > keepCount {
            let toDelete = checkpoints.suffix(from: keepCount)
            for url in toDelete {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    Self.logger.warning("Failed to delete old checkpoint \(url.lastPathComponent): \(error)")
                }
            }
        }
    }

    // MARK: - Private Helpers

    private func cleanupCheckpoint(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.warning("Failed to cleanup checkpoint \(url.lastPathComponent): \(error)")
        }
    }
}
