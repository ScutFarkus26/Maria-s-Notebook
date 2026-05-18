// BackupCoordinator.swift
// Top-level entry point for the Backup2 module. The UI talks to this.
//
// Responsibilities:
//   - Export: always writes v17 AEA (BackupWriter).
//   - Import: detects file format via AEA magic bytes, routes to:
//       * v17 → BackupReader + BackupImporter, wrapped in BackupTransactionManager
//       * v5–v16 → existing BackupService.importBackup (already wrapped by the
//         caller through BackupTransactionManager.executeImportWithRollback).
//   - Estimation + preview: delegated to legacy `BackupService` (the math and
//     analyzer code don't need to change for v17).
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

    // Underlying services. BackupService is retained because:
    //   - `previewImport` reuses its decode path (already handles v5–v16; will
    //     extend to v17 below by branching on format).
    //   - `importBackup` is delegated to for legacy `.mtbbackup` files.
    //   - `estimateBackupSize` is unchanged.
    //   - `BackupTransactionManager` calls back into `BackupService` for
    //     checkpoint creation + rollback (legacy format on disk).
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
    ///   - v5–v16: delegate to legacy `BackupService.previewImport`
    func previewImport(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: BackupService.RestoreMode,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> RestorePreview {
        if BackupArchive.isAEAFormat(at: url) {
            return try previewAEA(viewContext: viewContext, from: url, mode: mode, progress: progress)
        } else {
            return try await backupService.previewImport(
                viewContext: viewContext,
                from: url,
                mode: mode,
                password: nil,
                progress: progress
            )
        }
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
    /// `BackupTransactionManager`). Routes the actual import work to either
    /// the v17 path (AEA) or the legacy path (BackupService) based on file
    /// format. The rollback path always uses the legacy format because
    /// `BackupTransactionManager` writes its checkpoints via
    /// `BackupService.exportBackup` — those are v16 envelopes regardless of
    /// what the user is importing.
    @discardableResult
    func importBackup(
        viewContext: NSManagedObjectContext,
        from url: URL,
        mode: BackupService.RestoreMode,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> BackupOperationSummary {

        if BackupArchive.isAEAFormat(at: url) {
            return try await importAEA(
                viewContext: viewContext,
                from: url,
                mode: mode,
                progress: progress
            )
        } else {
            // Legacy v5–v16 path. Already wrapped by callers through
            // `BackupTransactionManager.executeImportWithRollback`, but this
            // entry point can also be used directly (and the transaction
            // manager will be invoked at the SettingsViewModel layer either way).
            return try await backupService.importBackup(
                viewContext: viewContext,
                from: url,
                mode: mode,
                password: nil,
                appRouter: appRouter,
                progress: progress
            )
        }
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
