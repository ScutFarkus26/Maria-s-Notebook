import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import OSLog

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct DataManagementGrid: View {
    private static let logger = Logger.settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel: SettingsViewModel

    init() {
        // Initialize with default dependencies - will be overridden by environment
        _viewModel = State(wrappedValue: SettingsViewModel(dependencies: AppDependenciesKey.defaultValue))
    }

    @SyncedAppStorage("Backup.encrypt") private var encryptBackups: Bool = false
    @AppStorage(UserDefaultsKeys.autoBackupEnabled) private var autoBackupEnabled = true
    @AppStorage(UserDefaultsKeys.autoBackupRetentionCount) private var autoBackupRetention = 10

    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingFolderImporter = false
    @State private var resultMessage: String?

    private var isWorking: Bool {
        (viewModel.backupProgress > 0 && viewModel.backupProgress < 1.0) ||
        (viewModel.importProgress > 0 && viewModel.importProgress < 1.0)
    }

    var body: some View {
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
                Task { await viewModel.previewImportedURL(modelContext: modelContext, url: url) }
            case .failure(let error):
                viewModel.importError = "Failed to select backup file: \(error.localizedDescription)"
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
                    } catch {
                        Self.logger.warning("Failed to set default backup folder: \(error, privacy: .public)")
                    }
                    viewModel.loadDefaultFolderName()
                }
            } catch {
                Self.logger.warning("Failed to get folder URL: \(error, privacy: .public)")
            }
        }
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
                Task { await viewModel.performImportConfirmed(modelContext: modelContext) }
            })
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
        .onAppear {
            viewModel.loadDefaultFolderName()
            viewModel.calculateEstimatedBackupSize(modelContext: modelContext)
        }
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
        .background(RoundedRectangle(cornerRadius: AppTheme.Spacing.small).fill(color.opacity(0.1)))
    }

    // MARK: - Backup Card

    private var backupCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                HStack {
                    Label("Backup", systemImage: "externaldrive.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.blue)
                    Spacer()
                    encryptionPill
                }

                if let size = viewModel.estimatedBackupSize {
                    Text(formatBytes(size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await viewModel.performExport(modelContext: modelContext, encryptBackups: encryptBackups) }
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

    private var encryptionPill: some View {
        Button { encryptBackups.toggle() } label: {
            HStack(spacing: AppTheme.Spacing.statusPillVertical) {
                Image(systemName: encryptBackups ? "lock.fill" : "lock.open")
                Text(encryptBackups ? "Encrypted" : "Public")
            }
            .font(.caption2)
            .padding(.horizontal, AppTheme.Spacing.statusPillHorizontal)
            .padding(.vertical, AppTheme.Spacing.statusPillVertical)
            .background(Capsule().fill(encryptBackups ? Color.green.opacity(0.15) : Color.primary.opacity(0.08)))
            .foregroundStyle(encryptBackups ? .green : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Restore Card

    private var restoreCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label("Restore", systemImage: SFSymbol.Action.arrowCounterclockwise)
                    .font(.subheadline.weight(.semibold))
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
            }
        }
    }

    // MARK: - Storage Card

    private var storageCard: some View {
        CompactGridCard {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Label("Storage", systemImage: SFSymbol.Document.folderFill)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.purple)
                    Spacer()
                    folderMenu
                }

                Text(viewModel.defaultFolderName.isEmpty ? "No folder selected" : viewModel.defaultFolderName)
                    .font(.caption)
                    .foregroundStyle(viewModel.defaultFolderName.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                if let date = viewModel.lastBackupDate {
                    Text("Last: \(date, style: .relative)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var folderMenu: some View {
        Menu {
            Button { showingFolderImporter = true } label: {
                Label("Choose Folder…", systemImage: SFSymbol.Document.folderBadgePlus)
            }
            if !viewModel.defaultFolderName.isEmpty {
                Button { openFolder() } label: {
                    Label("Open in Finder", systemImage: "arrow.up.forward.square")
                }
                Divider()
                Button(role: .destructive) { clearFolder() } label: {
                    Label("Clear", systemImage: SFSymbol.Action.xmarkCircle)
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
                        .font(.subheadline.weight(.semibold))
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
                .fill(Color.green.opacity(0.12))
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

    private func clearFolder() {
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
                    await viewModel.previewImportedURL(modelContext: modelContext, url: url)
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
