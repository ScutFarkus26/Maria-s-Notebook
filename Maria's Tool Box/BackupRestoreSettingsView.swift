import SwiftUI
import UniformTypeIdentifiers

struct BackupRestoreSettingsView: View {
    @Binding var encryptBackups: Bool
    @Binding var restoreMode: BackupService.RestoreMode
    @Binding var backupProgress: Double
    @Binding var backupMessage: String
    @Binding var importProgress: Double
    @Binding var importMessage: String
    @Binding var resultSummary: String?
    @Binding var defaultFolderName: String
    
    // New property to receive the date
    let lastBackupDate: Date?

    let performExport: () -> Void
    let presentImporter: () -> Void
    let chooseDefaultFolder: () -> Void
    let openDefaultFolder: () -> Void
    let clearDefaultFolder: () -> Void

    var body: some View {
        SettingsGroup(title: "Backup & Restore", systemImage: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 12) {
                // Display Last Backup Time
                HStack {
                    Text("Last Backup:")
                    Spacer()
                    if let date = lastBackupDate {
                        Text("\(date, style: .relative)")
                    } else {
                        Text("Never")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                
                Divider()

                Toggle("Encrypt Backups", isOn: $encryptBackups)
                Picker("Restore Mode", selection: $restoreMode) {
                    Text("Merge").tag(BackupService.RestoreMode.merge)
                    Text("Replace").tag(BackupService.RestoreMode.replace)
                }
                .pickerStyle(.segmented)
                HStack(spacing: 12) {
                    Button {
                        performExport()
                    } label: {
                        Label("Export Backup (Data Only)", systemImage: "externaldrive.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    Button {
                        presentImporter()
                    } label: {
                        Label("Import Backup…", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                if backupProgress > 0 && backupProgress < 1.0 {
                    ProgressView(value: backupProgress) { Text(backupMessage) }
                }
                if importProgress > 0 && importProgress < 1.0 {
                    ProgressView(value: importProgress) { Text(importMessage) }
                }
                if let summary = resultSummary {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Divider().padding(.vertical, 4)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "externaldrive")
                            .foregroundStyle(.secondary)
                        Text(defaultFolderName.isEmpty ? "No default folder selected" : "Default folder: \(defaultFolderName)")
                            .foregroundStyle(defaultFolderName.isEmpty ? .secondary : .primary)
                    }
                    HStack(spacing: 8) {
                        Button {
                            chooseDefaultFolder()
                        } label: {
                            Label("Choose Default Folder…", systemImage: "folder.badge.plus")
                        }
                        Button {
                            openDefaultFolder()
                        } label: {
                            Label("Open Default Folder", systemImage: "folder")
                        }
                        Button(role: .destructive) {
                            clearDefaultFolder()
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                    }
                }
            }
        }
    }
}

