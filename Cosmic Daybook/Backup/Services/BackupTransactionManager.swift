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
        /// A restore with no checkpoint (a Merge) that failed after its records
        /// were saved: they stay, so "nothing was changed" would be wrong.
        case importIncompleteAfterSaving(Error)

        /// What the guide reads. The underlying errors are logged where they
        /// are wrapped (`executeWithRollback`, `createCheckpoint`).
        public var errorDescription: String? {
            switch self {
            case .checkpointCreationFailed:
                return "Couldn't make a safety copy before restoring, so nothing was changed. Try again."
            case .rollbackFailed, .noCheckpointExists:
                return "The restore didn't finish, and your notebook couldn't be put back on its own. "
                    + "Restore your most recent backup from Settings \u{203A} Sync and backup."
            case .importFailed(let error, let checkpointURL):
                // A backup error that already says what went wrong ("This backup
                // file is damaged…") says it; anything else gets the outcome.
                if let explained = error as? any ExplainedBackupError, let text = explained.errorDescription {
                    return text
                }
                return checkpointURL == nil
                    ? "The restore didn't finish, so nothing was changed. Try again."
                    : "The restore didn't finish, so your notebook was put back the way it was. Nothing was lost."
            case .importIncompleteAfterSaving:
                return "The backup's records were restored, but the restore stopped before it finished. "
                    + "Check your notebook; restoring the same backup again is safe."
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
        let formatter = DateFormatters.iso8601DateTime
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let sanitizedName = operationName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
        let filename = "Checkpoint-\(sanitizedName)-\(timestamp).\(BackupFile.fileExtension)"
        let checkpointURL = checkpointDirectory.appendingPathComponent(filename)

        do {
            // No photos: a restore never removes one, so the checkpoint needn't
            // carry them back (and copying every photo would slow each restore).
            _ = try await BackupWriter.write(
                viewContext: viewContext,
                to: checkpointURL,
                includesPhotos: false,
                progress: progress ?? { _, _ in }
            )

            activeCheckpointURL = checkpointURL
            return checkpointURL
        } catch {
            Self.logger.error("Safety checkpoint failed: \(String(describing: error), privacy: .public)")
            throw TransactionError.checkpointCreationFailed(error)
        }
    }

    /// Wraps a caller-supplied import closure with the safety-checkpoint +
    /// rollback dance. The closure does the actual import (any format) and
    /// receives a scaled progress callback covering 15–95%.
    ///
    /// The checkpoint is restored only when the import failed after saving
    /// its records (`BackupRestoreSavedError`). A failure before that — a
    /// damaged file, a refusal, a type that wouldn't import — left the
    /// notebook as it was: the restore saves its clear and its records in one
    /// save and discards both when it fails first. Rebuilding the notebook
    /// from the checkpoint then would only delete and re-add every record (on
    /// every device) and drop the guide's unsaved edits; the unused
    /// checkpoint is removed instead.
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
            Self.logger.error("Restore failed: \(String(describing: error), privacy: .public)")
            throw await recover(from: error, checkpointURL: checkpointURL, viewContext: viewContext, progress: progress)
        }
    }

    /// What a failed import throws, after going back to the checkpoint when
    /// the import had saved its records (see `executeWithRollback`).
    private func recover(
        from error: any Error,
        checkpointURL: URL?,
        viewContext: NSManagedObjectContext,
        progress: @escaping BackupService.ProgressCallback
    ) async -> TransactionError {
        let saved = error as? BackupRestoreSavedError
        let underlying = saved?.underlying ?? error
        guard let checkpointURL, saved != nil else {
            if let checkpointURL { cleanupCheckpoint(at: checkpointURL) }
            activeCheckpointURL = nil
            // Saved with no checkpoint to go back to (a Merge): its records
            // stay. Otherwise nothing of the restore reached the store.
            if saved != nil { return .importIncompleteAfterSaving(underlying) }
            return .importFailed(underlying, checkpointURL: nil)
        }
        progress(0.96, "Import failed. Attempting rollback…")
        do {
            try await rollback(
                viewContext: viewContext,
                from: checkpointURL,
                progress: { subProgress, message in
                    progress(0.96 + (subProgress * 0.04), "Rollback: \(message)")
                }
            )
            return .importFailed(underlying, checkpointURL: checkpointURL)
        } catch let rollbackError as TransactionError {
            return rollbackError
        } catch {
            Self.logger.fault("Rollback failed: \(String(describing: error), privacy: .public)")
            return .rollbackFailed(error)
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

        // No `viewContext.rollback()` here: the failed restore already
        // discarded its own unsaved changes (`BackupService.importRows`), so
        // anything still unsaved is the guide's, and the checkpoint's restore
        // saves it first like any restore.
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
            _ = try await BackupImporter.restore(
                from: checkpointURL,
                into: viewContext,
                mode: .replace,
                appRouter: AppRouter.shared,
                progress: progress
            )
        } catch {
            Self.logger.fault("Rollback failed: \(String(describing: error), privacy: .public)")
            throw TransactionError.rollbackFailed(error)
        }
    }
}

/// A backup or restore error whose text already tells the guide what went
/// wrong, so a failed restore shows it rather than the general "didn't finish".
nonisolated protocol ExplainedBackupError: LocalizedError {}

nonisolated extension BackupArchive.ArchiveError: ExplainedBackupError {}
nonisolated extension BackupReader.ReadError: ExplainedBackupError {}
nonisolated extension BackupEncryptionKeyStore.KeyStoreError: ExplainedBackupError {}
