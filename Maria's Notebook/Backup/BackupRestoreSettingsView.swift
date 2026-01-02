import SwiftUI
import UniformTypeIdentifiers
import Foundation

struct BackupRestoreSettingsView: View {
    @Binding var encryptBackups: Bool
    @Binding var restoreMode: BackupService.RestoreMode
    @Binding var backupProgress: Double
    @Binding var backupMessage: String
    @Binding var importProgress: Double
    @Binding var importMessage: String
    @Binding var resultSummary: String?
    @Binding var defaultFolderName: String
    
    let lastBackupDate: Date?
    let estimatedBackupSize: Int64?

    let performExport: () -> Void
    let presentImporter: () -> Void
    let chooseDefaultFolder: () -> Void
    let openDefaultFolder: () -> Void
    let clearDefaultFolder: () -> Void

    // Automatic backup settings
    @AppStorage("AutoBackup.enabled") private var autoBackupEnabled = true
    @AppStorage("AutoBackup.retentionCount") private var autoBackupRetention = 10

    var body: some View {
        SettingsGroup(title: "Backup & Restore", systemImage: "arrow.triangle.2.circlepath") {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Status Section
                statusSection
                
                Divider()
                
                // MARK: - Backup Section
                backupSection
                
                Divider()
                
                // MARK: - Automatic Backups Section
                automaticBackupsSection
                
                Divider()
                
                // MARK: - Restore Section
                restoreSection
                
                Divider()
                
                // MARK: - Advanced Options
                advancedSection
                
                Divider()
                
                // MARK: - Default Folder
                defaultFolderSection
                
                // MARK: - Progress Indicators
                if backupProgress > 0 && backupProgress < 1.0 {
                    progressIndicator(progress: backupProgress, message: backupMessage)
                }
                
                if importProgress > 0 && importProgress < 1.0 {
                    progressIndicator(progress: importProgress, message: importMessage)
                }
                
                // MARK: - Result Summary
                if let summary = resultSummary, !summary.isEmpty {
                    resultSummaryView(summary)
                }
            }
        }
    }
    
    // MARK: - Status Section
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Text("Last Backup")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                if let date = lastBackupDate {
                    Text(date, style: .relative)
                        .font(.subheadline)
                        .fontWeight(.medium)
                } else {
                    Text("Never")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            
            // Backup verification status indicator
            if lastBackupDate != nil {
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text("Backup completed successfully")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Backup Section
    private var backupSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create Backup")
                .font(.headline)
            
            Button {
                performExport()
            } label: {
                Label("Export Backup", systemImage: "externaldrive.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Toggle("Encrypt Backups", isOn: $encryptBackups)
                .help("Encrypted backups require a password to restore")
            
            if let estimatedSize = estimatedBackupSize {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.ellipsis")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text("Estimated size: \(formatByteCount(estimatedSize))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            
            Text("Backups include all your data except imported documents and file attachments.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Helpers
    private func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
    
    // MARK: - Automatic Backups Section
    private var automaticBackupsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Automatic Backups")
                .font(.headline)
            
            Toggle("Enable Automatic Backups", isOn: $autoBackupEnabled)
                .help("Automatically create a backup when you quit the app")
            
            if autoBackupEnabled {
                HStack {
                    Text("Keep")
                        .font(.subheadline)
                    Stepper(value: $autoBackupRetention, in: 1...100, step: 1) {
                        Text("\(autoBackupRetention)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(minWidth: 40, alignment: .trailing)
                    }
                    Text(autoBackupRetention == 1 ? "backup" : "backups")
                        .font(.subheadline)
                    Spacer()
                }
                .help("Number of automatic backups to keep (older backups are automatically deleted)")
                
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Automatic backups are created when you quit the app and stored in:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("~/Documents/Backups/Auto/")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            } else {
                Text("Automatic backups are disabled. You can still create manual backups above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    // MARK: - Restore Section
    private var restoreSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore Backup")
                .font(.headline)
            
            Button {
                presentImporter()
            } label: {
                Label("Import Backup…", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Picker("Restore Mode", selection: $restoreMode) {
                Text("Merge").tag(BackupService.RestoreMode.merge)
                Text("Replace").tag(BackupService.RestoreMode.replace)
            }
            .pickerStyle(.segmented)
            .help(restoreMode == .merge ? "Add backup data to existing data, skipping duplicates" : "Replace all existing data with backup data")
            
            Text(restoreMode == .merge 
                 ? "Merge mode adds new records while keeping existing ones. Duplicate IDs are skipped."
                 : "Replace mode deletes all current data and restores from the backup. This action cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Advanced Section
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced")
                .font(.headline)
            
            Toggle(isOn: Binding(
                get: { UserDefaults.standard.bool(forKey: UserDefaultsKeys.backupAllowChecksumBypass) },
                set: { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.backupAllowChecksumBypass) }
            )) {
                Text("Allow checksum bypass")
            }
            .tint(.orange)
            .help("If a backup fails integrity validation, enabling this lets you import it anyway with a warning. Use only if you trust the file.")
            
            Text("Disable integrity checks for old or problematic backup files. Not recommended for normal use.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    // MARK: - Default Folder Section
    private var defaultFolderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                Text("Default Backup Folder")
                    .font(.headline)
            }
            
            if defaultFolderName.isEmpty {
                Text("No folder selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(defaultFolderName)
                        .font(.subheadline)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            }
            
            HStack(spacing: 8) {
                Button {
                    chooseDefaultFolder()
                } label: {
                    Label("Choose Folder…", systemImage: "folder.badge.plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                
                if !defaultFolderName.isEmpty {
                    Button {
                        openDefaultFolder()
                    } label: {
                        Label("Open", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                    
                    Button(role: .destructive) {
                        clearDefaultFolder()
                    } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }
            }
        }
    }
    
    // MARK: - Progress Indicator
    private func progressIndicator(progress: Double, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress) {
                Text(message)
                    .font(.subheadline)
            }
            .progressViewStyle(.linear)
            
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Result Summary
    private func resultSummaryView(_ summary: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.subheadline)
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.green.opacity(0.1))
        )
    }
}

