import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Define the custom UTType matching Info.plist
extension UTType {
    static let mariasBackup = UTType(exportedAs: "com.marias-notebook.backup")
}

struct BackupRestoreSectionView: View {
    private static let logger = Logger.backup
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: SettingsViewModel

    init() {
        // Initialize with default dependencies - will be overridden by environment
        _viewModel = State(wrappedValue: SettingsViewModel(dependencies: AppDependenciesKey.defaultValue))
    }
    @SyncedAppStorage("Backup.encrypt") private var encryptBackups: Bool = false

    // Export / Import state
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var showingFolderImporter = false
    @State private var folderRejection: BackupDestination.FolderRejection?
    @State private var migrationPrompt: BackupFolderMigration.Prompt?

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
            estimatedBackupSize: viewModel.estimatedBackupSize,
            performExport: {
                Task {
                    await viewModel.performExport(
                        viewContext: viewContext,
                        encryptBackups: encryptBackups
                    )
                }
            },
            presentImporter: {
                showingImporter = true
            },
            chooseDefaultFolder: {
                showingFolderImporter = true
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
                viewModel.importError = AppErrorMessages.backupMessage(for: error, operation: "save the backup")
            }
            viewModel.exportData = nil
            viewModel.backupProgress = 0; viewModel.backupMessage = ""
        }
        // MARK: - Importer (Backup File)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [
                .mariasBackup,
                UTType(filenameExtension: BackupFile.fileExtension) ?? .data,
                .data  // Fallback to allow selecting any file when iOS doesn't recognize custom UTType
            ]
        ) { result in
            switch result {
            case .success(let url):
                Task { await viewModel.previewImportedURL(viewContext: viewContext, url: url) }
            case .failure(let error):
                viewModel.importError = AppErrorMessages.backupMessage(for: error, operation: "open the backup file")
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
                        } catch let rejection as BackupDestination.FolderRejection {
                            folderRejection = rejection
                        } catch {
                            let desc = error.localizedDescription
                            Self.logger.error("Error setting default folder: \(desc, privacy: .public)")
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
        .alert(
            "Can't use that folder",
            isPresented: Binding(
                get: { folderRejection != nil },
                set: { if !$0 { folderRejection = nil } }
            ),
            presenting: folderRejection
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { rejection in
            Text(rejection.errorDescription ?? "")
        }
        .alert(
            "Move backups out of this folder?",
            isPresented: Binding(
                get: { migrationPrompt != nil },
                set: { if !$0 { migrationPrompt = nil } }
            ),
            presenting: migrationPrompt
        ) { prompt in
            Button("Move to iCloud Drive") {
                Task {
                    let result = await BackupFolderMigration.moveBackupsToManagedFolder(from: prompt.suspiciousFolder)
                    handleMigrationResult(result)
                }
            }
            Button("Keep using this folder", role: .cancel) {
                BackupFolderMigration.dismiss()
            }
        } message: { prompt in
            Text(migrationMessage(for: prompt))
        }
        .sheet(item: $viewModel.operationSummary) { (summary: BackupOperationSummary) in
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
                        Task { await viewModel.performImportConfirmed(viewContext: viewContext) }
                    }
                )
            }
        }
        .onChange(of: appRouter.navigationDestination) { _, newValue in
            if case .createBackup = newValue {
                Task { await viewModel.performExport(viewContext: viewContext, encryptBackups: encryptBackups) }
                appRouter.clearNavigation()
            } else if case .restoreBackup = newValue {
                showingImporter = true
                appRouter.clearNavigation()
            }
        }
        .onAppear {
            viewModel.loadDefaultFolderName()
            viewModel.calculateEstimatedBackupSize(viewContext: viewContext)
            if migrationPrompt == nil {
                migrationPrompt = BackupFolderMigration.pendingPrompt()
            }
        }
#if os(iOS)
        .onChange(of: viewModel.exportData) { _, newValue in
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

    private func migrationMessage(for prompt: BackupFolderMigration.Prompt) -> String {
        let path = prompt.suspiciousFolder.path
        let count = prompt.fileCount
        if count == 0 {
            return "Manual backups are saving to “\(path)”, which looks unsafe. " +
                   "Move to iCloud Drive › Maria's Notebook › Backups?"
        }
        let noun = count == 1 ? "backup" : "backups"
        return "\(count) \(noun) are saved in “\(path)”, which looks unsafe " +
               "(code repo, app bundle, or system folder). Move them to " +
               "iCloud Drive › Maria's Notebook › Backups?"
    }

    private func handleMigrationResult(_ result: BackupFolderMigration.MoveResult) {
        switch result {
        case .moved(let count, _):
            let noun = count == 1 ? "backup" : "backups"
            viewModel.resultSummary = "Moved \(count) \(noun) to iCloud Drive."
            ToastService.shared.showSuccess("Backups moved")
        case .nothingToMove:
            viewModel.resultSummary = "Cleared default folder. Future backups go to iCloud Drive."
        case .failed(let error):
            viewModel.importError = "Couldn't move backups: \(error.localizedDescription)"
        }
        viewModel.loadDefaultFolderName()
    }
}

#Preview {
    BackupRestoreSectionView()
}
