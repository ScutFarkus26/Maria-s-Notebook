import Foundation
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine

#if os(macOS)
import AppKit
#endif

@MainActor
final class SettingsViewModel: ObservableObject {
    // MARK: - Published UI State
    @Published var restoreMode: BackupService.RestoreMode = .merge
    @Published var backupProgress: Double = 0
    @Published var backupMessage: String = ""
    @Published var importProgress: Double = 0
    @Published var importMessage: String = ""
    @Published var resultSummary: String? = nil
    @Published var operationSummary: BackupOperationSummary? = nil
    @Published var restorePreviewData: RestorePreview? = nil
    @Published var defaultFolderName: String = ""
    @Published var exportData: Data? = nil
    @Published var importError: String? = nil
    @Published var estimatedBackupSize: Int64? = nil

    // Internal
    private let backupService = BackupService()
    private var pendingImportURL: URL? = nil
    private var exportURL: URL? = nil

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
    private static let backupFilenameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()

    func defaultBackupFilename() -> String {
        let formatter = Self.backupFilenameFormatter
        return "MariasNotebook_DataBackup_\(formatter.string(from: Date()))"
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
    func performExport(modelContext: ModelContext, encryptBackups: Bool) async {
        do {
            backupProgress = 0; backupMessage = "Preparing…"; resultSummary = nil
            let tmpName = defaultBackupFilename()
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent(tmpName)
                .appendingPathExtension(BackupFile.fileExtension)
            exportURL = tmp
            try? FileManager.default.removeItem(at: tmp)
            _ = try await backupService.exportBackup(
                modelContext: modelContext,
                to: tmp,
                password: encryptBackups ? "defaultPassword" : nil
            ) { [weak self] progress, message in
                guard let self else { return }
                Task { @MainActor in
                    self.backupProgress = progress
                    self.backupMessage = message
                }
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
                    try? FileManager.default.removeItem(at: tmp)
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
            if #available(macOS 12.0, *) {
                panel.allowedContentTypes = [UTType(filenameExtension: BackupFile.fileExtension) ?? .data]
            } else {
                panel.allowedFileTypes = [BackupFile.fileExtension]
            }
            let suggested = tmpName.hasSuffix("." + BackupFile.fileExtension) ? tmpName : (tmpName + "." + BackupFile.fileExtension)
            panel.nameFieldStringValue = suggested

            let response = panel.runModal()
            if response == .OK, let destURL = panel.url {
                var finalURL = destURL
                if finalURL.pathExtension.isEmpty {
                    finalURL = destURL.appendingPathExtension(BackupFile.fileExtension)
                }
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try? FileManager.default.removeItem(at: finalURL)
                }
                do {
                    try FileManager.default.copyItem(at: tmp, to: finalURL)
                    setLastBackupNow()
                    resultSummary = "Exported backup to \(finalURL.lastPathComponent)."
                    loadDefaultFolderName()
                } catch {
                    importError = "Failed to write backup: \(error.localizedDescription)"
                }
            } else {
                resultSummary = "Export canceled."
            }
            try? FileManager.default.removeItem(at: tmp)
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
                guard let self else { return }
                Task { @MainActor in
                    self.importProgress = p
                    self.importMessage = m
                }
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
                mode: restoreMode
            ) { [weak self] p, m in
                guard let self else { return }
                Task { @MainActor in
                    self.importProgress = p
                    self.importMessage = m
                }
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
            AppRouter.shared.requestBackfillIsPresented()
        } catch {
            importError = "Failed to restore: \(error.localizedDescription)"
        }
    }
}

