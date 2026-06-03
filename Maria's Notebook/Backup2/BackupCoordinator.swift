// BackupCoordinator.swift
// Top-level entry point for the Backup2 module. The UI talks to this.
//
// Responsibilities:
//   - Single app-facing entry point for backup and restore work.
//   - Export: always writes v17 AEA (BackupWriter).
//   - Import: wraps restore with safety-checkpoint + rollback, then routes to
//     the current v17 path via BackupReader + BackupImporter.
//   - Estimation, preview, verification, and status all live here so callers
//     don't have to know about multiple backup subsystems.
//
// This means the UI has one API to learn (`BackupCoordinator`) while the
// underlying decode path matches the file's format.

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

    /// Exports a v17 AEA backup. Synchronous on the inside (writes are
    /// I/O-bound and not CPU-heavy for normal-sized datasets) but exposed as
    /// `async` so callers can `await` and receive progress on the main actor.
    @discardableResult
    func exportBackup(
        viewContext: NSManagedObjectContext,
        to url: URL,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        return try BackupWriter.write(
            viewContext: viewContext,
            to: url,
            progress: progress
        )
    }

    // MARK: - Preview

    /// Returns the same `RestorePreview` shape the legacy decode path produced.
    /// Branches by file format:
    ///   - v17 AEA: decode + analyze
    ///   - non-AEA: reject manual import of legacy backup files
    func previewImport(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: BackupService.RestoreMode,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> RestorePreview {
        guard BackupArchive.isAEAFormat(at: url) else {
            throw ImportError.legacyManualImportNoLongerSupported
        }

        return try previewAEA(viewContext: viewContext, from: url, mode: mode, progress: progress)
    }

    private func previewAEA(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: BackupService.RestoreMode,
        progress: @escaping BackupService.ProgressCallback
    ) throws -> RestorePreview {
        progress(0.10, "Reading backup\u{2026}")
        let decoded = try BackupReader.read(from: url)

        progress(0.50, "Analyzing\u{2026}")
        let payload = try BackupImporter.reconstructPayload(from: decoded)
        let analysis = BackupPreviewAnalyzer.analyze(
            payload: payload,
            viewContext: viewContext,
            mode: mode,
            entityExists: { [self] type, id in
                do {
                    return (try self.backupService.fetchOne(type, id: id, using: viewContext)) != nil
                } catch {
                    return false
                }
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
            warnings: analysis.warnings
        )
    }

    // MARK: - Import

    /// Performs an import with safety-checkpoint + rollback (via the existing
    /// `BackupTransactionManager`). Routes the actual import work to the v17
    /// path (AEA) or rejects legacy manual imports.
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
        guard BackupArchive.isAEAFormat(at: url) else {
            throw ImportError.legacyManualImportNoLongerSupported
        }

        return try await importAEA(
            viewContext: viewContext,
            from: url,
            mode: mode,
            progress: progress
        )
    }

    private func importAEA(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: BackupService.RestoreMode,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }

        progress(0.10, "Reading v17 archive\u{2026}")
        let decoded = try BackupReader.read(from: url)

        return try await BackupImporter.importDecoded(
            decoded,
            from: url,
            into: viewContext,
            mode: mode,
            appRouter: appRouter,
            progress: progress
        )
    }
}
