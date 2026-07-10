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

@MainActor
@Observable
final class BackupCoordinator {
    private static let logger = Logger.backup

    private enum ImportError: LocalizedError {
        case legacyManualImportNoLongerSupported

        var errorDescription: String? {
            switch self {
            case .legacyManualImportNoLongerSupported:
                return "Legacy .mtbbackup files are no longer supported for manual import. " +
                    "Import a current backup created by this version of the app."
            }
        }
    }

    // Underlying services. BackupService is retained because:
    //   - `estimateBackupSize` still uses its shared payload collection logic.
    //   - BackupWriter / BackupImporter still reuse shared BackupService helpers.
    private let backupService: BackupService
    private let transactionManager: BackupTransactionManager
    private let appRouter: AppRouter

    init(
        backupService: BackupService,
        transactionManager: BackupTransactionManager,
        appRouter: AppRouter
    ) {
        self.backupService = backupService
        self.transactionManager = transactionManager
        self.appRouter = appRouter
    }

    // MARK: - Size Estimation

    func estimateBackupSize(viewContext: NSManagedObjectContext) -> Int64 {
        backupService.estimateBackupSize(viewContext: viewContext)
    }

    func backupStatus() -> BackupStatus {
        BackupVerification.getBackupStatus()
    }

    func verifyBackup(at url: URL) -> Result<BackupInfo, Error> {
        BackupVerification.verifyBackup(at: url)
    }

    // MARK: - Export

    /// Exports a v19 encrypted backup. Payload collection happens on the main
    /// actor (Core Data); encoding, encryption, write, and verification run
    /// off-main inside BackupWriter.
    @discardableResult
    func exportBackup(
        viewContext: NSManagedObjectContext,
        to url: URL,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        return try await BackupWriter.write(
            viewContext: viewContext,
            to: url,
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
        let archive = try await BackupImporter.decodeArchive(at: url)

        progress(0.50, "Analyzing\u{2026}")
        // One ID-set fetch per entity type instead of one fetch per record —
        // the index is built lazily for only the types the payload contains.
        let idIndex = EntityIDIndexCache(context: viewContext)
        let analysis = BackupPreviewAnalyzer.analyze(
            payload: archive.payload,
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

    /// Performs an import with safety-checkpoint + rollback (via the existing
    /// `BackupTransactionManager`). Routes the actual import work to the
    /// current decode path or rejects legacy manual imports.
    @discardableResult
    func importBackup(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: BackupService.RestoreMode,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        try await transactionManager.executeWithRollback(
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
        let archive = try await BackupImporter.decodeArchive(at: url)

        return try await BackupImporter.importDecoded(
            archive,
            from: url,
            into: viewContext,
            mode: mode,
            appRouter: appRouter,
            progress: progress
        )
    }
}
