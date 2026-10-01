// swiftlint:disable file_length
import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

#if os(macOS)
import AppKit
#endif

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
private struct DataManagementPanel: View {
    private static let logger = Logger.settings
    @Environment(\.dependencies) private var dependencies
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
    private var viewContext: NSManagedObjectContext { notebook.coreDataStack.viewContext }

    @AppStorage(UserDefaultsKeys.autoBackupEnabled) private var autoBackupEnabled = true
    @AppStorage(UserDefaultsKeys.backupIncludesNotePhotos) private var backupIncludesNotePhotos = true
    @AppStorage(UserDefaultsKeys.autoBackupRetentionCount) private var autoBackupRetention = 10
    // Defaults match AutoBackupManager's.
    @AppStorage(UserDefaultsKeys.autoBackupScheduledEnabled) private var timedBackupsEnabled = false
    @AppStorage(UserDefaultsKeys.autoBackupIntervalHours) private var timedBackupHours = 4

    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingFolderImporter = false
    @State private var resultMessage: BackupResultNote?
    @State private var folderRejection: BackupDestination.FolderRejection?
    @State private var migrationPrompt: BackupFolderMigration.Prompt?
    @State private var isDropTargeted: Bool = false

    private var isWorking: Bool {
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
                        handleMigrationResult(result)
                    }
                }
                Button("Keep using this folder", role: .cancel) {
                    BackupFolderMigration.dismiss()
                }
            } message: { prompt in
                Text(migrationMessage(for: prompt))
            }
            .alert("Error", isPresented: Binding(
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
            case .failure:
                viewModel.importError = "Couldn't access the selected backup file. Try selecting it again."
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
                viewModel.importError = AppErrorMessages.backupMessage(for: error, operation: "save the backup")
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
                        folderRejection = rejection
                    } catch {
                        Self.logger.warning("Failed to set default backup folder: \(error, privacy: .public)")
                    }
                    viewModel.loadDefaultFolderName()
                }
            } catch {
                Self.logger.warning("Failed to get folder URL: \(error, privacy: .public)")
            }
        }
    }

    private func migrationMessage(for prompt: BackupFolderMigration.Prompt) -> String {
        let path = prompt.suspiciousFolder.path
        let count = prompt.fileCount
        if count == 0 {
            return "Manual backups are saving to “\(path)”, which looks unsafe. " +
                   "Move to iCloud Drive › Cosmic Daybook › Backups?"
        }
        let noun = count == 1 ? "backup" : "backups"
        return "\(count) \(noun) are saved in “\(path)”, which looks unsafe " +
               "(code repo, app bundle, or system folder). Move them to " +
               "iCloud Drive › Cosmic Daybook › Backups?"
    }

    private func handleMigrationResult(_ result: BackupFolderMigration.MoveResult) {
        switch result {
        case .moved(let count, _):
            let noun = count == 1 ? "backup" : "backups"
            resultMessage = .init(text: "Moved \(count) \(noun) to iCloud Drive.", tone: .success)
            dependencies.toastService.showSuccess("Backups moved")
        case .nothingToMove:
            resultMessage = .init(text: "New backups will go to iCloud Drive.", tone: .success)
        case .failed(let error):
            resultMessage = .init(text: "Couldn't move backups: \(error.localizedDescription)", tone: .failure)
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

    // MARK: - Restore Card

    private var restoreCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label("Restore", systemImage: SFSymbol.Action.arrowCounterclockwise)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppColors.warning)

                Picker("How to restore", selection: $viewModel.restoreMode) {
                    Text("Merge").tag(BackupService.RestoreMode.merge)
                    Text("Replace").tag(BackupService.RestoreMode.replace)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)
                .labelsHidden()

                // Both explained before the choice; the chosen one reads brighter.
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                    restoreModeLine(
                        .merge,
                        "**Merge:** Add what's in the backup and keep everything else."
                    )
                    restoreModeLine(
                        .replace,
                        "**Replace:** Make this device match the backup exactly."
                    )
                }

                Button {
                    #if os(macOS)
                    presentMacFilePicker()
                    #else
                    showingImporter = true
                    #endif
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isWorking)

                Button {
                    Task { await viewModel.restoreMostRecentAutoBackup(viewContext: viewContext) }
                } label: {
                    Label("Restore last automatic backup", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(isWorking)
            }
        }
    }

    private func restoreModeLine(_ mode: BackupService.RestoreMode, _ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(viewModel.restoreMode == mode ? .primary : .secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Storage Card

    private var storageCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Label("Storage", systemImage: SFSymbol.CDDocument.folderFill)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.tint)
                    Spacer()
                    folderMenu
                }

                Text(viewModel.defaultFolderName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let date = viewModel.lastBackupDate {
                    Text("Last backup \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    let daysSince = AppCalendar.shared.dateComponents(
                        [.day], from: date, to: Date()
                    ).day ?? 0
                    if daysSince >= 7 {
                        Label(
                            "Backup is \(daysSince) days old",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption2)
                        .foregroundStyle(AppColors.warning)
                    }
                } else {
                    Label(
                        "No backup yet",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.caption2)
                    .foregroundStyle(AppColors.warning)
                }
            }
        }
    }

    private var folderMenu: some View {
        Menu {
            Button { showingFolderImporter = true } label: {
                Label("Choose another folder…", systemImage: SFSymbol.CDDocument.folderBadgePlus)
            }
            #if os(macOS)
            Button { openFolder() } label: {
                Label("Show in Finder", systemImage: "arrow.up.forward.square")
            }
            #endif
            if BackupDestination.resolveBookmarkedFolder() != nil {
                Divider()
                Button { resetToDefault() } label: {
                    Label("Reset to iCloud Drive", systemImage: "icloud")
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .accessibilityLabel("Backup folder options")
    }

    // MARK: - Auto-Backup Card

    private var autoBackupCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Label("Automatic backups", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppColors.success)
                    Spacer()
                    // Title is hidden visually but read by VoiceOver — an empty
                    // title would announce as an unlabeled switch.
                    Toggle("Automatic backups", isOn: $autoBackupEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }

                footnote(Self.leavingTriggerText)
                    .opacity(autoBackupEnabled ? 1 : 0.4)

                // The timer is its own switch: AutoBackupManager runs it
                // whether or not the quit/leave backups above are on.
                Toggle(isOn: $timedBackupsEnabled) {
                    Text(timedBackupLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if timedBackupsEnabled {
                    Stepper("Hours between backups", value: $timedBackupHours, in: 1...24)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .controlSize(.small)
                    footnote("While Cosmic Daybook is open. Skips a turn when the device is hot or in Low Power Mode.")
                }

                footnote("Any automatic backup is skipped when nothing has changed since the last one.")

                // Retention trims every automatic backup, timed ones included.
                Stepper(value: $autoBackupRetention, in: 1...50) {
                    Text(retentionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .controlSize(.small)
                .opacity(autoBackupEnabled || timedBackupsEnabled ? 1 : 0.4)
                .disabled(!autoBackupEnabled && !timedBackupsEnabled)

                // Every backup, manual or automatic, follows this.
                Toggle(isOn: $backupIncludesNotePhotos) {
                    Text("Include note photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                footnote("Photos make each backup larger: every kept backup holds its own copy.")
            }
        }
        // AutoBackupManager reads the switch and the interval only when it
        // arms the next timed backup, so restart it from the new values.
        .onChange(of: timedBackupsEnabled) { rescheduleTimedBackups() }
        .onChange(of: timedBackupHours) { rescheduleTimedBackups() }
    }

    /// When the switch in the card's header backs up.
    private static var leavingTriggerText: String {
        #if os(macOS)
        "Saves a backup each time you quit Cosmic Daybook."
        #else
        "Saves a backup when you leave the app, and now and then while it's charging."
        #endif
    }

    private var timedBackupLabel: String {
        timedBackupHours == 1 ? "Back up every hour" : "Back up every \(timedBackupHours) hours"
    }

    private var retentionLabel: String {
        autoBackupRetention == 1 ? "Keep the last backup" : "Keep the last \(autoBackupRetention) backups"
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func rescheduleTimedBackups() {
        dependencies.autoBackupManager.startScheduledBackups(viewContext: dependencies.viewContext)
    }

    // MARK: - Result Banner

    private func resultBanner(_ note: BackupResultNote) -> some View {
        let (symbol, color): (String, Color) = switch note.tone {
        case .success: (SFSymbol.Action.checkmarkCircleFill, AppColors.success)
        case .neutral: ("info.circle.fill", Color.secondary)
        case .failure: (SFSymbol.Status.exclamationmarkTriangleFill, AppColors.destructive)
        }
        return HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(note.text)
                .font(.caption)
                .lineLimit(note.tone == .failure ? nil : 1)
            Spacer()
            Button { resultMessage = nil } label: {
                Image(systemName: SFSymbol.Action.xmark)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, AppTheme.Spacing.small + 2)
        .padding(.vertical, AppTheme.Spacing.sm)
        .surface(
            AppTheme.Spacing.small,
            fill: color.opacity(UIConstants.OpacityConstants.medium),
            style: .continuous
        )
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    #if os(macOS)
    private func openFolder() {
        if let url = BackupDestination.resolveDefaultFolder() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
    #endif

    private func resetToDefault() {
        BackupDestination.clearDefaultFolder()
        viewModel.loadDefaultFolderName()
    }

    #if os(macOS)
    private func presentMacFilePicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        panel.allowedContentTypes = [
            UTType(exportedAs: "com.cosmic-daybook.backup"),
            UTType(filenameExtension: BackupFile.fileExtension) ?? .data,
            .data  // Fallback to allow selecting any file when macOS doesn't recognize custom UTType
        ]
        panel.begin { response in
            if response == .OK, let url = panel.url {
                Task { @MainActor in
                    await viewModel.previewImportedURL(viewContext: viewContext, url: url)
                }
            }
        }
    }
    #endif
}

// MARK: - Compact Grid Card

private struct CompactGridCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .cardStyle(cornerRadius: AppTheme.Spacing.small + 2, padding: SettingsStyle.compactPadding)
    }
}

// Ensure RestorePreview is Identifiable for sheets
extension RestorePreview: Identifiable {
    public var id: String { "preview" }
}
