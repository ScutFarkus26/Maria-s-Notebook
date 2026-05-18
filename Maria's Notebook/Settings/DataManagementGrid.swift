// swiftlint:disable file_length
import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// swiftlint:disable:next type_body_length
struct DataManagementGrid: View {
    private static let logger = Logger.settings
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: SettingsViewModel

    init() {
        // Initialize with default dependencies - will be overridden by environment
        _viewModel = State(wrappedValue: SettingsViewModel(dependencies: AppDependenciesKey.defaultValue))
    }

    @AppStorage(UserDefaultsKeys.autoBackupEnabled) private var autoBackupEnabled = true
    @AppStorage(UserDefaultsKeys.autoBackupRetentionCount) private var autoBackupRetention = 10

    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingFolderImporter = false
    @State private var resultMessage: String?
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
                Task { @MainActor in
                    await viewModel.previewImportedURL(viewContext: viewContext, url: url)
                }
                return true
            } isTargeted: { targeted in
                isDropTargeted = targeted
            }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            // Progress bar or result banner (inline)
            if isWorking {
                progressBar
            } else if let message = resultMessage {
                resultBanner(message)
            }

            // Compact 2x2 grid
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: SettingsStyle.groupSpacing),
                    GridItem(.flexible(), spacing: SettingsStyle.groupSpacing)
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
                UTType(exportedAs: "com.marias-notebook.backup"),
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
            contentType: UTType(exportedAs: "com.marias-notebook.backup"),
            defaultFilename: viewModel.defaultBackupFilename()
        ) { _ in }
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
            resultMessage = "Moved \(count) \(noun) to iCloud Drive."
            ToastService.shared.showSuccess("Backups moved")
        case .nothingToMove:
            resultMessage = "Cleared default folder. Future backups go to iCloud Drive."
        case .failed(let error):
            resultMessage = "Couldn't move backups: \(error.localizedDescription)"
        }
        viewModel.loadDefaultFolderName()
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        let (progress, color): (Double, Color) = viewModel.backupProgress > 0
            ? (viewModel.backupProgress, .blue)
            : (viewModel.importProgress, .orange)

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
        .background(RoundedRectangle(cornerRadius: AppTheme.Spacing.small).fill(color.opacity(UIConstants.OpacityConstants.light)))
    }

    // MARK: - Backup Card

    private var backupCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label("Backup", systemImage: "externaldrive.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.blue)

                if let size = viewModel.estimatedBackupSize {
                    Text(formatBytes(size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await viewModel.performExport(viewContext: viewContext) }
                } label: {
                    Text("Create Backup")
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

                Picker("", selection: $viewModel.restoreMode) {
                    Text("Merge").tag(BackupService.RestoreMode.merge)
                    Text("Replace").tag(BackupService.RestoreMode.replace)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)

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
                    Label("Restore Latest Auto", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(isWorking)
            }
        }
    }

    // MARK: - Storage Card

    private var storageCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Label("Storage", systemImage: SFSymbol.CDDocument.folderFill)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.purple)
                    Spacer()
                    folderMenu
                }

                Text(viewModel.defaultFolderName)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let date = viewModel.lastBackupDate {
                    Text("Last: \(date, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    let daysSince = Calendar.current.dateComponents(
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
                        "No backup found",
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
                Label("Choose Custom Folder…", systemImage: SFSymbol.CDDocument.folderBadgePlus)
            }
            Button { openFolder() } label: {
                Label("Open in Finder", systemImage: "arrow.up.forward.square")
            }
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
    }

    // MARK: - Auto-Backup Card

    private var autoBackupCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Label("Auto-Backup", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppColors.success)
                    Spacer()
                    Toggle("", isOn: $autoBackupEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(SettingsStyle.toggleScale)
                        .labelsHidden()
                }

                HStack {
                    Text("Keep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(value: $autoBackupRetention, in: 1...50) {
                        Text("\(autoBackupRetention)")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                    .controlSize(.small)
                }
                .opacity(autoBackupEnabled ? 1 : 0.4)
                .disabled(!autoBackupEnabled)
            }
        }
    }

    // MARK: - Result Banner

    private func resultBanner(_ message: String) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                .foregroundStyle(AppColors.success)
            Text(message)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button { resultMessage = nil } label: {
                Image(systemName: SFSymbol.Action.xmark)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Spacing.small + 2)
        .padding(.vertical, AppTheme.Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Spacing.small, style: .continuous)
                .fill(Color.green.opacity(UIConstants.OpacityConstants.medium))
        )
    }

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func openFolder() {
        #if os(macOS)
        if let url = BackupDestination.resolveDefaultFolder() {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        #else
        if let url = BackupDestination.resolveDefaultFolder() {
            UIApplication.shared.open(url)
        }
        #endif
    }

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
            UTType(exportedAs: "com.marias-notebook.backup"),
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
