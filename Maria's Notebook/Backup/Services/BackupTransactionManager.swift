// BackupTransactionManager.swift
// Handles transaction rollback for failed imports and pre-import safety backups

import Foundation
import CoreData
import OSLog

/// Manages backup transactions with rollback capability.
/// Creates safety checkpoints before destructive operations and provides
/// automatic recovery on failure.
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
                    let name = url.lastPathComponent
                    return "Import failed: \(error.localizedDescription). A safety backup was created at \(name)."
                }
                return "Import failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Initialization

    public init() {}

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
    ///   - viewContext: The model context to backup
    ///   - operationName: Name of the operation (for filename)
    ///   - progress: Optional progress callback
    /// - Returns: URL of the checkpoint file
    public func createCheckpoint(
        viewContext: NSManagedObjectContext,
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
            _ = try await BackupWriter.write(
                viewContext: viewContext,
                to: checkpointURL,
                progress: progress ?? { _, _ in }
            )

            activeCheckpointURL = checkpointURL
            return checkpointURL
        } catch {
            throw TransactionError.checkpointCreationFailed(error)
        }
    }

    /// Wraps a caller-supplied import closure with the safety-checkpoint +
    /// rollback dance. The closure does the actual import (any format) and
    /// receives a scaled progress callback covering 15–95%.
    /// On failure, the checkpoint is restored through the current backup flow.
    public func executeWithRollback(
        viewContext: NSManagedObjectContext,
        mode: BackupService.RestoreMode,
        shouldCreateCheckpoint createCheckpointOption: Bool? = nil,
        progress: @escaping BackupService.ProgressCallback,
        makeCheckpoint: ((NSManagedObjectContext, BackupService.ProgressCallback) async throws -> URL)? = nil,
        importBody: (@escaping BackupService.ProgressCallback) async throws -> BackupOperationSummary
    ) async throws -> BackupOperationSummary {

        let shouldCreateCheckpoint = createCheckpointOption ?? (mode == .replace)
        var checkpointURL: URL?

        if shouldCreateCheckpoint {
            progress(0.0, "Creating safety checkpoint…")
            do {
                // A failed checkpoint leaves no recovery point. The import that
                // follows can be destructive (.replace deletes all existing data
                // first), so we MUST abort rather than proceed — deleting with no
                // way back is the one outcome to avoid at all costs. The checkpoint
                // maker is injectable so this safety path can be tested.
                let checkpointMaker = makeCheckpoint ?? { context, checkpointProgress in
                    try await self.createCheckpoint(
                        viewContext: context,
                        operationName: "PreImport",
                        progress: checkpointProgress
                    )
                }
                checkpointURL = try await checkpointMaker(viewContext) { subProgress, message in
                    progress(subProgress * 0.15, message)
                }
            } catch {
                Logger.backup.error("Checkpoint creation failed \u{2014} aborting before destructive import: \(error)")
                throw error
            }
        }

        progress(0.15, "Starting import…")
        do {
            let summary = try await importBody({ subProgress, message in
                progress(0.15 + (subProgress * 0.80), message)
            })

            progress(0.95, "Cleaning up…")
            if let checkpointURL {
                cleanupCheckpoint(at: checkpointURL)
            }
            activeCheckpointURL = nil
            progress(1.0, "Import complete")
            return summary

        } catch {
            if let checkpointURL {
                progress(0.96, "Import failed. Attempting rollback…")
                do {
                    try await rollback(
                        viewContext: viewContext,
                        from: checkpointURL,
                        progress: { subProgress, message in
                            progress(0.96 + (subProgress * 0.04), "Rollback: \(message)")
                        }
                    )
                    throw TransactionError.importFailed(error, checkpointURL: checkpointURL)
                } catch let rollbackError as TransactionError {
                    throw rollbackError
                } catch {
                    throw TransactionError.rollbackFailed(error)
                }
            } else {
                throw TransactionError.importFailed(error, checkpointURL: nil)
            }
        }
    }

    /// Manually rolls back to a checkpoint.
    ///
    /// - Parameters:
    ///   - viewContext: The model context to restore
    ///   - checkpointURL: The checkpoint file to restore from
    ///   - progress: Progress callback
    public func rollback(
        viewContext: NSManagedObjectContext,
        from checkpointURL: URL,
        progress: @escaping BackupService.ProgressCallback
    ) async throws {
        guard FileManager.default.fileExists(atPath: checkpointURL.path) else {
            throw TransactionError.noCheckpointExists
        }

        // Drop any partial unsaved changes from the failed import before re-importing
        // the checkpoint — otherwise those zombie inserts/deletes get re-saved alongside
        // the restore and corrupt it.
        viewContext.rollback()

        try await importCheckpoint(
            from: checkpointURL,
            into: viewContext,
            progress: progress
        )
    }

    // MARK: - Private Helpers

    private func cleanupCheckpoint(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.warning("Failed to cleanup checkpoint \(url.lastPathComponent): \(error)")
        }
    }

    private func importCheckpoint(
        from checkpointURL: URL,
        into viewContext: NSManagedObjectContext,
        progress: @escaping BackupService.ProgressCallback
    ) async throws {
        do {
            guard BackupArchive.isBackupArchive(at: checkpointURL) else {
                throw NSError(
                    domain: "BackupTransactionManager",
                    code: 3001,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Checkpoint is not in the current backup format."
                    ]
                )
            }

            progress(0.05, "Reading checkpoint…")
            let archive = try await BackupImporter.decodeArchive(at: checkpointURL)
            _ = try await BackupImporter.importDecoded(
                archive,
                from: checkpointURL,
                into: viewContext,
                mode: .replace,
                appRouter: AppRouter.shared,
                progress: progress
            )
        } catch {
            throw TransactionError.rollbackFailed(error)
        }
    }
}
