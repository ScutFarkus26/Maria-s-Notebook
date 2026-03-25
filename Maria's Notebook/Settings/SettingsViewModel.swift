import Foundation
import SwiftUI
import SwiftData
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
        defaultFolderName = BackupDestination.resolveDefaultFolder()?.lastPathComponent ?? ""
    }
    
    /// Calculates estimated backup size asynchronously
    func calculateEstimatedBackupSize(modelContext: ModelContext) {
        Task { @MainActor in
            estimatedBackupSize = backupService.estimateBackupSize(modelContext: modelContext)
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
    func performExport(modelContext: ModelContext, encryptBackups: Bool) async {
        do {
            backupProgress = 0; backupMessage = "Preparing…"; resultSummary = nil
            let tmpName = defaultBackupFilename()
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(tmpName)
                .appendingPathExtension(BackupFile.fileExtension)
            exportURL = tmp
            safeRemoveItem(at: tmp, context: "performExport-cleanup")
            _ = try await backupService.exportBackup(
                modelContext: modelContext,
                to: tmp,
                password: encryptBackups ? "defaultPassword" : nil
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
                    importError = "Failed to write backup: \(error.localizedDescription)"
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
            importError = "Failed to export: \(error.localizedDescription)"
        }
    }

    // MARK: - Import / Preview
    func previewImportedURL(modelContext: ModelContext, url: URL) async {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            importProgress = 0
            importMessage = "Reading file…"
            resultSummary = nil
            let preview = try await backupService.previewImport(
                modelContext: modelContext,
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
            importError = "Failed to analyze backup: \(error.localizedDescription)"
        }
    }

    func performImportConfirmed(modelContext: ModelContext) async {
        guard let url = pendingImportURL else { return }
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            importProgress = 0
            importMessage = "Starting…"
            resultSummary = nil
            let summary = try await backupService.importBackup(
                modelContext: modelContext,
                from: url,
                mode: restoreMode,
                appRouter: dependencies.appRouter
            ) { [weak self] p, m in
                self?.importProgress = p
                self?.importMessage = m
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
            importError = "Failed to restore: \(error.localizedDescription)"
        }
    }

    // MARK: - Error Handling Helpers

    private func safeRemoveItem(at url: URL, context: String = #function) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            Self.logger.warning(
                "Failed to remove item at \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)"
            )
        }
    }
}
