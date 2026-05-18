import Foundation
import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

#if os(macOS)
import AppKit
#endif

@Observable
@MainActor
final class SettingsViewModel {
    private static let logger = Logger.settings

    // MARK: - UI State
    var restoreMode: BackupService.RestoreMode = .merge
    var backupProgress: Double = 0
    var backupMessage: String = ""
    var importProgress: Double = 0
    var importMessage: String = ""
    var resultSummary: String?
    var operationSummary: BackupOperationSummary?
    var restorePreviewData: RestorePreview?
    var defaultFolderName: String = ""
    var exportData: Data?
    var importError: String?
    var estimatedBackupSize: Int64?

    // Internal
    private let dependencies: AppDependencies
    private var backupService: BackupService { dependencies.backupService }
    private var transactionManager: BackupTransactionManager { dependencies.backupTransactionManager }
    private var coordinator: BackupCoordinator { dependencies.backupCoordinator }
    private var pendingImportURL: URL?
    private var exportURL: URL?
    
    // MARK: - Initialization
    
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Last Backup Date
    private static let lastBackupKey = "LastBackupTimeInterval"
    var lastBackupDate: Date? {
        let t = UserDefaults.standard.double(forKey: Self.lastBackupKey)
        return t > 0 ? Date(timeIntervalSinceReferenceDate: t) : nil
    }
    func setLastBackupNow() {
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: Self.lastBackupKey)
    }

    // MARK: - Helpers
    func defaultBackupFilename() -> String {
        "MariasNotebook_DataBackup_\(DateFormatters.backupFilename.string(from: Date()))"
    }

    func loadDefaultFolderName() {
        if let custom = BackupDestination.resolveBookmarkedFolder() {
            defaultFolderName = custom.lastPathComponent
        } else {
            defaultFolderName = BackupFolderStorage.displayLabel()
        }
    }
    
    /// Calculates estimated backup size asynchronously
    func calculateEstimatedBackupSize(viewContext: NSManagedObjectContext) {
        Task { @MainActor in
            estimatedBackupSize = backupService.estimateBackupSize(viewContext: viewContext)
        }
    }

    private func uniquedURL(in folder: URL, base: String, ext: String) -> URL {
        var candidate = folder.appendingPathComponent(base).appendingPathExtension(ext)
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) (\(i))").appendingPathExtension(ext)
            i += 1
        }
        return candidate
    }

    // MARK: - Export
    // swiftlint:disable:next function_body_length
    func performExport(viewContext: NSManagedObjectContext) async {
        do {
            backupProgress = 0; backupMessage = "Preparing…"; resultSummary = nil
            let tmpName = defaultBackupFilename()
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(tmpName)
                .appendingPathExtension(BackupFile.fileExtension)
            exportURL = tmp
            safeRemoveItem(at: tmp, context: "performExport-cleanup")
            // Export through Backup2 — produces v17 AEA-framed files.
            // Legacy `.mtbbackup` decode (v5–v16) is still supported on import.
            // At-rest protection comes from FileVault / iOS Data Protection / iCloud Drive.
            _ = try await coordinator.exportBackup(
                viewContext: viewContext,
                to: tmp
            ) { [weak self] progress, message in
                self?.backupProgress = progress
                self?.backupMessage = message
            }
            // Attempt seamless save to default folder if configured
            if let folder = BackupDestination.resolveDefaultFolder() {
                let needsAccess = folder.startAccessingSecurityScopedResource()
                defer { if needsAccess { folder.stopAccessingSecurityScopedResource() } }
                let base = tmpName
                let dest = uniquedURL(in: folder, base: base, ext: BackupFile.fileExtension)
                do {
                    try FileManager.default.copyItem(at: tmp, to: dest)
                    setLastBackupNow()
                    resultSummary = "Exported backup to \(dest.lastPathComponent)."
                    ToastService.shared.showSuccess("Backup saved successfully")
                    safeRemoveItem(at: tmp, context: "performExport-seamlessSave")
                    loadDefaultFolderName()
                    return
                } catch {
                    // Fall back to interactive save below
                }
            }
#if os(macOS)
            // macOS: Present a Save dialog and write the backup
            let panel = NSSavePanel()
            panel.title = "Save Backup"
            panel.canCreateDirectories = true
            panel.isExtensionHidden = false
            panel.allowedContentTypes = [UTType(filenameExtension: BackupFile.fileExtension) ?? .data]
            let ext = BackupFile.fileExtension
            let suggested = tmpName.hasSuffix("." + ext) ? tmpName : (tmpName + "." + ext)
            panel.nameFieldStringValue = suggested

            let response = panel.runModal()
            if response == .OK, let destURL = panel.url {
                var finalURL = destURL
                if finalURL.pathExtension.isEmpty {
                    finalURL = destURL.appendingPathExtension(BackupFile.fileExtension)
                }
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    safeRemoveItem(at: finalURL, context: "performExport-overwrite")
                }
                do {
                    try FileManager.default.copyItem(at: tmp, to: finalURL)
                    setLastBackupNow()
                    resultSummary = "Exported backup to \(finalURL.lastPathComponent)."
                    ToastService.shared.showSuccess("Backup saved successfully")
                    loadDefaultFolderName()
                } catch {
                    importError = AppErrorMessages.backupMessage(for: error, operation: "save the backup")
                }
            } else {
                resultSummary = "Export canceled."
            }
            safeRemoveItem(at: tmp, context: "performExport-macOSCleanup")
#else
            // iOS/iPadOS: provide data for SwiftUI fileExporter to present a save sheet
            let data = try Data(contentsOf: tmp)
            exportData = data
#endif
        } catch {
            importError = AppErrorMessages.backupMessage(for: error, operation: "export your backup")
        }
    }

    // MARK: - Import / Preview
    func previewImportedURL(viewContext: NSManagedObjectContext, url: URL) async {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            importProgress = 0
            importMessage = "Reading file…"
            resultSummary = nil
            // Coordinator picks the right decode path for the file format
            // (v17 AEA vs legacy v5–v16 JSON envelope).
            let preview = try await coordinator.previewImport(
                viewContext: viewContext,
                from: url,
                mode: restoreMode
            ) { [weak self] p, m in
                self?.importProgress = p
                self?.importMessage = m
            }
            // Reset progress and present preview
            importProgress = 0
            importMessage = ""
            restorePreviewData = preview
            pendingImportURL = url
        } catch {
            importError = AppErrorMessages.backupMessage(for: error, operation: "read the backup file")
        }
    }

    func performImportConfirmed(viewContext: NSManagedObjectContext) async {
        guard let url = pendingImportURL else { return }
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            importProgress = 0
            importMessage = "Starting…"
            resultSummary = nil
            // Route through the transaction manager so `.replace` mode gets a safety
            // checkpoint + automatic rollback on import failure. The coordinator
            // detects whether the file is v17 (AEA) or v5–v16 (legacy envelope)
            // and chooses the right decode path.
            let coordinatorRef = coordinator
            let summary = try await transactionManager.executeWithRollback(
                viewContext: viewContext,
                mode: restoreMode,
                shouldCreateCheckpoint: restoreMode == .replace,
                progress: { [weak self] p, m in
                    self?.importProgress = p
                    self?.importMessage = m
                }
            ) { stepProgress in
                try await coordinatorRef.importBackup(
                    viewContext: viewContext,
                    from: url,
                    mode: self.restoreMode,
                    progress: stepProgress
                )
            }
            restorePreviewData = nil
            pendingImportURL = nil
            importError = nil
            setLastBackupNow()
            resultSummary = "Import complete. Restored data successfully."
            operationSummary = BackupOperationSummary(
                kind: .import,
                fileName: summary.fileName,
                formatVersion: summary.formatVersion,
                encryptUsed: summary.encryptUsed,
                createdAt: summary.createdAt,
                entityCounts: summary.entityCounts,
                warnings: summary.warnings
            )
            dependencies.appRouter.requestBackfillIsPresented()
        } catch {
            importError = AppErrorMessages.backupMessage(for: error, operation: "restore your backup")
        }
    }

    // MARK: - Error Handling Helpers

    private func safeRemoveItem(at url: URL, context: String = #function) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where
            (error.domain == NSPOSIXErrorDomain && error.code == 2) ||
            (error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError) {
            // File already gone — nothing to clean up.
        } catch {
            Self.logger.warning(
                "Failed to remove item at \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)"
            )
        }
    }
}
