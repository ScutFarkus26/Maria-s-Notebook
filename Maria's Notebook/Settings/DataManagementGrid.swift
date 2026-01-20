import SwiftUI
import SwiftData
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct DataManagementGrid: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = SettingsViewModel()
    
    // Persisted Settings
    @SyncedAppStorage("Backup.encrypt") private var encryptBackups: Bool = false
    @AppStorage("AutoBackup.enabled") private var autoBackupEnabled = true
    @AppStorage("AutoBackup.retentionCount") private var autoBackupRetention = 10
    @AppStorage("Backup.allowChecksumBypass") private var allowChecksumBypass = false

    // Sheet State
    @State private var showingImporter = false
    @State private var showingExporter = false
    @State private var showingFolderImporter = false
    @State private var showAdvancedAlert = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            
            // MARK: - Card 1: Create Backup
            InteractiveCard(title: "Backup", systemImage: "externaldrive.badge.plus") {
                if viewModel.backupProgress > 0 && viewModel.backupProgress < 1.0 {
                    ProgressView(value: viewModel.backupProgress) {
                        Text(viewModel.backupMessage).font(.caption).lineLimit(1)
                    }
                } else {
                    VStack(spacing: 12) {
                        // Metadata Row: Size + Encrypt Toggle
                        HStack {
                            if let size = viewModel.estimatedBackupSize {
                                Text(formatBytes(size))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Calculating...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            
                            Spacer()
                            
                            // Compact Encrypt Toggle
                            Button(action: { encryptBackups.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: encryptBackups ? "lock.fill" : "lock.open")
                                    Text(encryptBackups ? "Encrypted" : "Public")
                                }
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(encryptBackups ? Color.green.opacity(0.15) : Color.gray.opacity(0.1))
                                .foregroundStyle(encryptBackups ? Color.green : Color.primary)
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }

                        Button(action: {
                            Task { await viewModel.performExport(modelContext: modelContext, encryptBackups: encryptBackups) }
                        }) {
                            Text("Create Backup")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            // Context menu for rarely used "Checksum" option
            .contextMenu {
                Toggle("Allow Checksum Bypass (Advanced)", isOn: $allowChecksumBypass)
            }

            // MARK: - Card 2: Restore
            InteractiveCard(title: "Restore", systemImage: "arrow.triangle.2.circlepath", color: .orange) {
                if viewModel.importProgress > 0 && viewModel.importProgress < 1.0 {
                    ProgressView(value: viewModel.importProgress) {
                        Text(viewModel.importMessage).font(.caption).lineLimit(1)
                    }
                } else {
                    VStack(spacing: 8) {
                        Spacer()
                        
                        // Mode Picker
                        Picker("Mode", selection: $viewModel.restoreMode) {
                            Text("Merge").tag(BackupService.RestoreMode.merge)
                            Text("Replace").tag(BackupService.RestoreMode.replace)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        
                        // Checksum Bypass Toggle
                        Toggle(isOn: $allowChecksumBypass) {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                                Text("Skip Checksum Validation")
                                    .font(.caption)
                            }
                        }
                        .toggleStyle(.switch)
                        .help("Allow restoring backups with checksum mismatches. Use only if you trust the file.")

                        Button(action: {
                            #if os(macOS)
                            presentMacFilePicker()
                            #else
                            showingImporter = true
                            #endif
                        }) {
                            Label("Import File…", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            // MARK: - Card 3: Storage / Default Folder
            InteractiveCard(title: "Storage", systemImage: "folder.fill", color: .purple) {
                VStack(alignment: .leading, spacing: 4) {
                    if !viewModel.defaultFolderName.isEmpty {
                        Text(viewModel.defaultFolderName)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No default folder")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack {
                        // Last Backup Time
                        Group {
                            if let date = viewModel.lastBackupDate {
                                Text("Last: \(date, style: .relative)")
                            } else {
                                Text("Last: Never")
                            }
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        
                        Spacer()
                        
                        // Consolidated Action Menu
                        Menu {
                            Button { showingFolderImporter = true } label: {
                                Label("Change Folder…", systemImage: "folder.badge.plus")
                            }
                            
                            if !viewModel.defaultFolderName.isEmpty {
                                Button { openFolder() } label: {
                                    Label("Open in Finder", systemImage: "arrow.up.right.square")
                                }
                                Divider()
                                Button(role: .destructive) { clearFolder() } label: {
                                    Label("Clear Selection", systemImage: "xmark.circle")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .font(.title3)
                                .foregroundStyle(Color.accentColor)
                        }
                        .menuStyle(.borderlessButton)
                    }
                }
            }

            // MARK: - Card 4: Automatic Backups
            InteractiveCard(title: "Auto-Backup", systemImage: "timer", color: .blue) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("On Quit")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("Enabled", isOn: $autoBackupEnabled)
                            .labelsHidden()
                            .scaleEffect(0.8)
                    }
                    
                    if autoBackupEnabled {
                        Stepper(value: $autoBackupRetention, in: 1...50) {
                            Text("Keep recent: \(autoBackupRetention)")
                                .font(.caption)
                                .monospacedDigit()
                        }
                    } else {
                        Text("Disabled")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                    }
                }
            }
        }
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [
                UTType(exportedAs: "com.marias-notebook.backup"),
                UTType(filenameExtension: "mbk") ?? .data
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
            if let url = try? result.get().first {
                _ = url.startAccessingSecurityScopedResource()
                try? BackupDestination.setDefaultFolder(url)
                viewModel.loadDefaultFolderName()
            }
        }
        .sheet(item: $viewModel.operationSummary) { summary in
            BackupSummaryView(summary: summary)
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
    
    // MARK: - Helpers
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
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
        if #available(macOS 12.0, *) {
            panel.allowedContentTypes = [
                UTType(exportedAs: "com.marias-notebook.backup"),
                UTType(filenameExtension: "mbk") ?? .data
            ]
        } else {
            panel.allowedFileTypes = ["mbk"]
        }
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

// Ensure RestorePreview is Identifiable for sheets
extension RestorePreview: Identifiable {
    public var id: String { "preview" }
}

