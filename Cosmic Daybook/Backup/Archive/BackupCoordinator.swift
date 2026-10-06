// BackupCoordinator.swift
// Top-level entry point for archive backup and restore. The UI talks to this.
//
// Responsibilities:
//   - Single app-facing entry point for backup and restore work.
//   - Export: always writes v19 encrypted archives (BackupWriter).
//   - Import: wraps restore with safety-checkpoint + rollback, then routes to
//     the current decode path via BackupImporter.
//   - Estimation, preview, verification, and status all live here so callers
//     don't have to know about multiple backup subsystems.
//
// Archive decode/encode runs off the main actor (see BackupWriter/
// BackupImporter); only Core Data work and UI signaling happen on main.

import Foundation
import CoreData
import OSLog

@Observable
final class BackupCoordinator {
    /// Explained: a restore failing on it says why, not just that it didn't finish.
    private nonisolated enum ImportError: ExplainedBackupError {
        case legacyManualImportNoLongerSupported

        var errorDescription: String? {
            switch self {
            case .legacyManualImportNoLongerSupported:
                return "This backup is from an old version of the app and can't be restored. " +
                    "Choose a newer backup."
            }
        }
    }

    // Underlying services. BackupService is retained because:
    //   - `estimateBackupSize` still uses its shared payload collection logic.
    //   - BackupWriter / BackupImporter still reuse shared BackupService helpers.
    private let backupService: BackupService
    private let transactionManager: BackupTransactionManager
    private let appRouter: AppRouter
    /// Where `BackupRestoreGate` reads this device's first-download flag.
    private let restoreGateDefaults: UserDefaults

    init(
        backupService: BackupService,
        transactionManager: BackupTransactionManager,
        appRouter: AppRouter,
        restoreGateDefaults: UserDefaults = .standard
    ) {
        self.backupService = backupService
        self.transactionManager = transactionManager
        self.appRouter = appRouter
        self.restoreGateDefaults = restoreGateDefaults
    }

    // MARK: - Size Estimation

    func estimateBackupSize(viewContext: NSManagedObjectContext) -> Int64 {
        backupService.estimateBackupSize(viewContext: viewContext)
    }

    func backupStatus() -> BackupStatus {
        BackupVerification.getBackupStatus()
    }

    // MARK: - Export

    /// Exports a v19 encrypted backup. Payload collection happens on the main
    /// actor (Core Data); encoding, encryption, write, and verification run
    /// off-main inside BackupWriter. `stopsWhenCancelled` is for the iPad's
    /// overnight background task only (see `BackupWriter.write`).
    @discardableResult
    func exportBackup(
        viewContext: NSManagedObjectContext,
        to url: URL,
        stopsWhenCancelled: Bool = false,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        return try await BackupWriter.write(
            viewContext: viewContext,
            to: url,
            stopsWhenCancelled: stopsWhenCancelled,
            progress: progress
        )
    }

    // MARK: - Preview

    /// Returns the same `RestorePreview` shape the legacy decode path produced.
    /// Branches by file format:
    ///   - v17+ archive: decode + analyze
    ///   - anything else: reject manual import of legacy backup files
    func previewImport(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: BackupService.RestoreMode,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> RestorePreview {
        guard BackupArchive.isBackupArchive(at: url) else {
            throw ImportError.legacyManualImportNoLongerSupported
        }

        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        progress(0.10, "Reading backup\u{2026}")
        // Counts and IDs only, one entry at a time: the preview never needed
        // the records themselves (see BackupPreviewDigest).
        let archive = try await BackupImporter.decodePreview(at: url)

        progress(0.50, "Analyzing\u{2026}")
        // One ID-set fetch per entity type instead of one fetch per record —
        // the index is built lazily for only the types the payload contains.
        let idIndex = EntityIDIndexCache(context: viewContext)
        let analysis = BackupPreviewAnalyzer.analyze(
            digest: archive.digest,
            viewContext: viewContext,
            mode: mode,
            entityExists: { type, id in
                idIndex.exists(type, id: id)
            }
        )

        progress(1.0, "Done")
        return RestorePreview(
            mode: mode.rawValue,
            entityInserts: analysis.inserts,
            entitySkips: analysis.skips,
            entityDeletes: analysis.deletes,
            totalInserts: analysis.totalInserts,
            totalDeletes: analysis.totalDeletes,
            warnings: analysis.warnings + archive.warnings
        )
    }

    // MARK: - Import

    /// Which notebook a restore fills.
    enum RestoreTarget {
        /// The notebook open in the app (Settings › Sync and backup).
        case openNotebook
        /// A new notebook the database-error screen made for the restore,
        /// in place of one that wouldn't open (`FreshNotebookRestore`).
        case freshNotebook
    }

    /// Performs an import with safety-checkpoint + rollback (via the existing
    /// `BackupTransactionManager`). Routes the actual import work to the
    /// current decode path or rejects legacy manual imports. Refused, before
    /// any checkpoint, while `BackupRestoreGate` says this device can't
    /// restore (first download under way, or not the lead guide's notebook).
    @discardableResult
    func importBackup(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: BackupService.RestoreMode,
        target: RestoreTarget = .openNotebook,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        if let reason = restoreBlocker(in: viewContext, target: target) {
            throw BackupRestoreGate.Refusal(reason: reason)
        }
        return try await transactionManager.executeWithRollback(
            viewContext: viewContext,
            mode: mode,
            shouldCreateCheckpoint: mode == .replace,
            progress: progress
        ) { stepProgress in
            try await self.performImport(
                viewContext: viewContext,
                from: url,
                mode: mode,
                progress: stepProgress
            )
        }
    }

    /// `BackupRestoreGate`'s reason this restore can't start, or nil.
    ///
    /// The first-download refusal (#32) is waived for a fresh notebook, on
    /// purpose. It keeps a restore out of a store an iCloud download is still
    /// filling, where the download would go on adding its copies beside the
    /// restored ones. The database-error screen's restore fills a new store of
    /// its own, opened without iCloud and only while iCloud sync is off on
    /// this device (`FreshNotebookRestore`), so no download reaches it; the
    /// device's first-download flag, whatever it says, is about the notebook
    /// that wouldn't open. The waiver holds only while the store really is out
    /// of iCloud's reach. The lead-guide check applies as everywhere.
    private func restoreBlocker(in context: NSManagedObjectContext, target: RestoreTarget) -> String? {
        let waivesFirstDownload = target == .freshNotebook && !BackupRestoreScope.syncsWithICloud(context)
        return BackupRestoreGate.blocker(
            firstDownloadPending: !waivesFirstDownload && FirstDownloadGate.isPending(defaults: restoreGateDefaults),
            role: CDClassroomMembership.currentRole(in: context)
        )
    }

    private func performImport(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: BackupService.RestoreMode,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        guard BackupArchive.isBackupArchive(at: url) else {
            throw ImportError.legacyManualImportNoLongerSupported
        }

        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        progress(0.10, "Reading archive\u{2026}")
        return try await BackupImporter.restore(
            from: url,
            into: viewContext,
            mode: mode,
            appRouter: appRouter,
            progress: progress
        )
    }
}
