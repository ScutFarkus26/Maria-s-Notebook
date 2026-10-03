import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

/// Sync and backup › Backups: back up, restore, the backup folder and
/// automatic backups.
struct DataManagementGrid: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.notebookDependencies) private var notebookDependencies
    /// Made once, from the guide's own notebook's dependencies (see
    /// `DataManagementPanel.notebook`), when the card first appears; the
    /// environment isn't readable in `init`.
    @State private var viewModel: SettingsViewModel?

    var body: some View {
        if let viewModel {
            DataManagementPanel(viewModel: viewModel)
        } else {
            Color.clear
                .frame(height: 0)
                .onAppear { viewModel = SettingsViewModel(dependencies: notebookDependencies ?? dependencies) }
        }
    }
}

// swiftlint:disable:next type_body_length
struct DataManagementPanel: View {
    private static let logger = Logger.settings
    @Environment(\.dependencies) var dependencies
    @Environment(\.notebookDependencies) private var notebookDependencies
    @Environment(\.isSampleClassroom) private var isSampleClassroom
    @Bindable var viewModel: SettingsViewModel

    /// Backup and restore always act on the guide's own notebook, as the
    /// menu's Create Backup and Restore Data do (they're off in Sample
    /// Class). On iOS Settings lives inside the window, whose context and
    /// dependencies are Sample Class's while it shows: a backup there was of
    /// the made-up class, and a restore wrote into it through a second,
    /// separate dependency graph.
    private var notebook: AppDependencies { notebookDependencies ?? dependencies }
    var viewContext: NSManagedObjectContext { notebook.coreDataStack.viewContext }

    @AppStorage(UserDefaultsKeys.autoBackupEnabled) var autoBackupEnabled = true
    @AppStorage(UserDefaultsKeys.backupIncludesNotePhotos) var backupIncludesNotePhotos = true
    @AppStorage(UserDefaultsKeys.autoBackupRetentionCount) var autoBackupRetention = 10
    // Defaults match AutoBackupManager's.
    @AppStorage(UserDefaultsKeys.autoBackupScheduledEnabled) var timedBackupsEnabled = false
    @AppStorage(UserDefaultsKeys.autoBackupIntervalHours) var timedBackupHours = 4

    @State var showingImporter = false
    @State private var showingExporter = false
    @State var showingFolderImporter = false
    @State var resultMessage: BackupResultNote?
    @State private var folderRejection: BackupDestination.FolderRejection?
    @State private var migrationPrompt: BackupFolderMigration.Prompt?
    @State private var isDropTargeted: Bool = false

    var isWorking: Bool {
        (viewModel.backupProgress > 0 && viewModel.backupProgress < 1.0) ||
        (viewModel.importProgress > 0 && viewModel.importProgress < 1.0)
    }

    var body: some View {
        contentWithAlerts
            .sheet(item: $viewModel.operationSummary) { summary in
                BackupSummaryView(summary: summary)
            }
            .onChange(of: viewModel.resultSummary) { _, newValue in
                if let summary = newValue {
                    resultMessage = summary
                    viewModel.resultSummary = nil
                }
            }
            .sheet(item: $viewModel.restorePreviewData) { preview in
                RestorePreviewView(preview: preview, onCancel: { viewModel.restorePreviewData = nil }, onConfirm: {
                    Task { await viewModel.performImportConfirmed(viewContext: viewContext) }
                })
            }
            .onAppear {
                viewModel.loadDefaultFolderName()
                viewModel.calculateEstimatedBackupSize(viewContext: viewContext)
                if migrationPrompt == nil {
                    migrationPrompt = BackupFolderMigration.pendingPrompt()
                }
            }
#if os(macOS)
            // Drag a .mtbbackup file in from Finder to start a restore.
            // Same code path as the file-picker import.
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                Task {
                    await viewModel.previewImportedURL(viewContext: viewContext, url: url)
                }
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                                .fill(Color.accentColor.opacity(0.06))
                        )
                        .allowsHitTesting(false)
                }
            }
#endif
    }

    // MARK: - Alerts

    private var contentWithAlerts: some View {
        fileContent
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
                        let result = await BackupFolderMigration
                            .moveBackupsToManagedFolder(from: prompt.suspiciousFolder)
                        handleMigrationResult(result, expected: prompt.fileCount)
                    }
                }
                Button("Keep using this folder", role: .cancel) {
                    BackupFolderMigration.dismiss()
                }
            } message: { prompt in
                Text(migrationMessage(for: prompt))
            }
            .alert(viewModel.importErrorTitle, isPresented: Binding(
                get: { viewModel.importError != nil },
                set: { if !$0 { viewModel.importError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                if let error = viewModel.importError {
                    Text(error)
                }
            }
    }

    // MARK: - Core Content + File Modifiers

    private var fileContent: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            if isSampleClassroom {
                Label("Backup and restore use your own class, not Sample Class.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Progress bar or result banner (inline)
            if isWorking {
                progressBar
            } else if let note = resultMessage {
                resultBanner(note)
            }

            // Compact 2x2 grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SettingsStyle.groupSpacing, alignment: .top),
                    GridItem(.flexible(), spacing: SettingsStyle.groupSpacing, alignment: .top)
                ],
                spacing: SettingsStyle.groupSpacing
            ) {
                backupCard
                restoreCard
                storageCard
                autoBackupCard
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [
                UTType(exportedAs: "com.cosmic-daybook.backup"),
                UTType(filenameExtension: BackupFile.fileExtension) ?? .data,
                .data  // Fallback to allow selecting any file when iOS doesn't recognize custom UTType
            ]
        ) { result in
            switch result {
            case .success(let url):
                Task { await viewModel.previewImportedURL(viewContext: viewContext, url: url) }
            case .failure(let error):
                Self.logger.warning("Backup file picker failed: \(error, privacy: .public)")
                viewModel.importErrorTitle = "Couldn't Restore"
                viewModel.importError = "Couldn't open the backup file you chose. Choose it again and try once more."
            }
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: viewModel.exportData.map { BackupPackageDocument(data: $0) },
            contentType: UTType(exportedAs: "com.cosmic-daybook.backup"),
            defaultFilename: viewModel.defaultBackupFilename()
        ) { result in
            switch result {
            case .success:
                viewModel.setLastBackupNow()
                viewModel.resultSummary = BackupResultNote(text: "Saved the backup.", tone: .success)
            case .failure(let error as CocoaError) where error.code == .userCancelled:
                viewModel.resultSummary = BackupResultNote(text: "Backup canceled.", tone: .neutral)
            case .failure(let error):
                viewModel.showBackupFailure(error, operation: "save the backup")
            }
            viewModel.exportData = nil
        }
        #if os(iOS)
        // `performExport` hands over the file this way when the backup folder
        // can't be written (macOS shows its own Save panel instead).
        .onChange(of: viewModel.exportData) { _, data in
            showingExporter = data != nil
        }
        #endif
        .fileImporter(
            isPresented: $showingFolderImporter,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            do {
                if let url = try result.get().first {
                    _ = url.startAccessingSecurityScopedResource()
                    do {
                        try BackupDestination.setDefaultFolder(url)
                    } catch let rejection as BackupDestination.FolderRejection {
                        Self.logger.notice("Backup folder refused: \(String(describing: rejection), privacy: .public)")
                        folderRejection = rejection
                    } catch {
                        Self.logger.warning("Failed to set default backup folder: \(error, privacy: .public)")
                        resultMessage = .init(
                            text: "Couldn't use that folder for backups. Choose it again, or pick another one.",
                            tone: .failure
                        )
                    }
                    viewModel.loadDefaultFolderName()
                }
            } catch {
                Self.logger.warning("Failed to get folder URL: \(error, privacy: .public)")
                resultMessage = .init(
                    text: "Couldn't open the folder you chose. Choose it again and try once more.", tone: .failure
                )
            }
        }
    }

    private func migrationMessage(for prompt: BackupFolderMigration.Prompt) -> String {
        let folder = prompt.suspiciousFolder.lastPathComponent
        let count = prompt.fileCount
        if count == 0 {
            return "Backups are set to save in a folder that isn't safe for them (“\(folder)”). " +
                   "Save them in iCloud Drive › Cosmic Daybook › Backups instead?"
        }
        let them = count == 1 ? "Your backup is" : "Your \(count) backups are"
        return "\(them) in a folder that isn't safe for them (“\(folder)”). " +
               "Move \(count == 1 ? "it" : "them") to iCloud Drive › Cosmic Daybook › Backups?"
    }

    private func handleMigrationResult(_ result: BackupFolderMigration.MoveResult, expected: Int) {
        // The files that wouldn't copy stay where they were (logged by the move).
        switch result {
        case .moved(0, _) where expected > 0:
            resultMessage = .init(
                text: "Couldn't move the backups. They're still in the old folder. "
                    + "New backups will go to iCloud Drive.",
                tone: .failure
            )
        case .moved(let count, _) where count < expected:
            resultMessage = .init(
                text: "Moved \(count) of \(expected) backups to iCloud Drive. The rest couldn't be moved "
                    + "and are still in the old folder.",
                tone: .failure
            )
        case .moved(let count, _):
            let noun = count == 1 ? "backup" : "backups"
            resultMessage = .init(text: "Moved \(count) \(noun) to iCloud Drive.", tone: .success)
            dependencies.toastService.showSuccess("Backups moved")
        case .nothingToMove:
            resultMessage = .init(text: "New backups will go to iCloud Drive.", tone: .success)
        case .failed(let error):
            Self.logger.error("Moving backups failed: \(String(describing: error), privacy: .public)")
            resultMessage = .init(text: "Couldn't move the backups. They're still in the old folder.", tone: .failure)
        }
        viewModel.loadDefaultFolderName()
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        let (progress, color): (Double, Color) = viewModel.backupProgress > 0
            ? (viewModel.backupProgress, AppColors.info)
            : (viewModel.importProgress, AppColors.warning)

        return HStack(spacing: AppTheme.Spacing.small) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(color)
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AppTheme.Spacing.small + 2)
        .padding(.vertical, AppTheme.Spacing.sm)
        .surface(AppTheme.Spacing.small, fill: color.opacity(UIConstants.OpacityConstants.light))
    }

    // MARK: - Backup Card

    private var backupCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label("Backup", systemImage: "externaldrive.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColors.info)

                if let size = viewModel.estimatedBackupSize {
                    Text("Estimated size: \(formatBytes(size))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await viewModel.performExport(viewContext: viewContext) }
                } label: {
                    Text("Back up now")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isWorking)
            }
        }
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
