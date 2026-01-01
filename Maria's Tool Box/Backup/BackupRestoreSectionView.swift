import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import Combine
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Define the custom UTType matching Info.plist
extension UTType {
    static let mariasBackup = UTType(exportedAs: "com.marias-toolbox.backup")
}

struct BackupRestoreSectionView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = SettingsViewModel()
    @AppStorage("Backup.encrypt") private var encryptBackups: Bool = false

    // Export / Import state
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingFolderImporter = false

    private var exportDocument: BackupPackageDocument? { viewModel.exportData.map { BackupPackageDocument(data: $0) } }

    var body: some View {
        BackupRestoreSettingsView(
            encryptBackups: $encryptBackups,
            restoreMode: $viewModel.restoreMode,
            backupProgress: $viewModel.backupProgress,
            backupMessage: $viewModel.backupMessage,
            importProgress: $viewModel.importProgress,
            importMessage: $viewModel.importMessage,
            resultSummary: $viewModel.resultSummary,
            defaultFolderName: $viewModel.defaultFolderName,
            lastBackupDate: viewModel.lastBackupDate,
            performExport: { Task { await viewModel.performExport(modelContext: modelContext, encryptBackups: encryptBackups) } },
            presentImporter: {
#if os(macOS)
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowsMultipleSelection = false
                panel.canCreateDirectories = false
                if #available(macOS 12.0, *) {
                    panel.allowedContentTypes = [UTType(filenameExtension: BackupFile.fileExtension) ?? .data]
                } else {
                    panel.allowedFileTypes = [BackupFile.fileExtension]
                }
                if panel.runModal() == .OK, let url = panel.url {
                    Task { await viewModel.previewImportedURL(modelContext: modelContext, url: url) }
                }
#else
                showingImporter = true
#endif
            },
            chooseDefaultFolder: {
#if os(macOS)
                let panel = NSOpenPanel()
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    try? BackupDestination.setDefaultFolder(url)
                    viewModel.loadDefaultFolderName()
                }
#else
                showingFolderImporter = true
#endif
            },
            openDefaultFolder: {
#if os(macOS)
                if let url = BackupDestination.resolveDefaultFolder() {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
#else
                if let url = BackupDestination.resolveDefaultFolder() {
                    UIApplication.shared.open(url)
                }
#endif
            },
            clearDefaultFolder: {
                BackupDestination.clearDefaultFolder()
                viewModel.loadDefaultFolderName()
            }
        )
        // MARK: - Exporter
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .mariasBackup,
            defaultFilename: viewModel.defaultBackupFilename()
        ) { result in
            switch result {
            case .success:
                viewModel.setLastBackupNow()
                viewModel.resultSummary = "Exported backup successfully."
            case .failure(let error):
                viewModel.importError = "Failed to write backup: \(error.localizedDescription)"
            }
            viewModel.exportData = nil
            viewModel.backupProgress = 0; viewModel.backupMessage = ""
        }
        // MARK: - Importer (Backup File)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [
                .mariasBackup,
                UTType(filenameExtension: BackupFile.fileExtension) ?? .data
            ]
        ) { result in
            switch result {
            case .success(let url):
                Task { await viewModel.previewImportedURL(modelContext: modelContext, url: url) }
            case .failure(let error):
                viewModel.importError = "Failed to restore: \(error.localizedDescription)"
            }
        }
        // MARK: - Folder Importer (Default Folder)
        .fileImporter(
            isPresented: $showingFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            Task { @MainActor in
                switch result {
                case .success(let urls):
                    // Fixed: Extract single URL from array
                    if let url = urls.first {
                        let needsAccess = url.startAccessingSecurityScopedResource()
                        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
                        do {
                            try BackupDestination.setDefaultFolder(url)
                            viewModel.loadDefaultFolderName()
                        } catch {
                            print("Error setting default folder: \(error)")
                        }
                    }
                case .failure:
                    break
                }
            }
        }
        // MARK: - Alerts and Sheets
        .alert("Error", isPresented: isErrorAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.importError ?? "Unknown error")
        }
        .sheet(item: $viewModel.operationSummary) { summary in
            BackupSummaryView(summary: summary)
        }
        .sheet(isPresented: isRestorePreviewPresented) {
            if let preview = viewModel.restorePreviewData {
                RestorePreviewView(
                    preview: preview,
                    onCancel: {
                        viewModel.restorePreviewData = nil
                    },
                    onConfirm: {
                        Task { await viewModel.performImportConfirmed(modelContext: modelContext) }
                    }
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("CreateBackupRequested"))) { _ in
            Task { await viewModel.performExport(modelContext: modelContext, encryptBackups: encryptBackups) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("RestoreBackupRequested"))) { _ in
            showingImporter = true
        }
        .onAppear {
            viewModel.loadDefaultFolderName()
        }
#if os(iOS)
        .onChange(of: viewModel.exportData) { newValue in
            showingExporter = (newValue != nil)
        }
#endif
    }

    // Extracted Bindings
    private var isErrorAlertPresented: Binding<Bool> {
        Binding<Bool>(
            get: { viewModel.importError != nil },
            set: { if !$0 { viewModel.importError = nil } }
        )
    }

    private var isRestorePreviewPresented: Binding<Bool> {
        Binding<Bool>(
            get: { viewModel.restorePreviewData != nil },
            set: { if !$0 { viewModel.restorePreviewData = nil } }
        )
    }
}

#Preview {
    BackupRestoreSectionView()
}
