import SwiftUI
import Foundation

/// A view that displays backup status and allows verification of backup files
struct BackupStatusView: View {
    @State private var backupStatus: BackupStatus?
    @State private var verificationResult: Result<BackupInfo, Error>?
    @State private var isVerifying = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backup Status")
                .font(.title2)
                .bold()
            
            if let status = backupStatus {
                statusSection(status: status)
            } else {
                ProgressView("Loading backup status...")
            }
            
            if let result = verificationResult {
                verificationSection(result: result)
            }
            
            if let status = backupStatus, let autoBackupURL = status.mostRecentAutoBackupURL {
                Divider()
                
                Button {
                    verifyBackup(at: autoBackupURL)
                } label: {
                    Label("Verify Most Recent Auto-Backup", systemImage: "checkmark.shield")
                }
                .buttonStyle(.bordered)
                .disabled(isVerifying)
            }
        }
        .padding()
        .onAppear {
            loadBackupStatus()
        }
    }
    
    private func statusSection(status: BackupStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.fill")
                    .foregroundStyle(.secondary)
                Text("Last Backup")
                    .font(.headline)
                Spacer()
                if let date = status.lastBackupDate {
                    Text(date, style: .relative)
                        .fontWeight(.medium)
                } else {
                    Text("Never")
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(.secondary)
                Text("Auto-Backup Directory")
                    .font(.headline)
                Spacer()
                if status.autoBackupDirectoryExists {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColors.success)
                } else {
                    Text("Not found")
                        .foregroundStyle(.secondary)
                }
            }
            
            if let autoBackupURL = status.mostRecentAutoBackupURL {
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Most Recent Auto-Backup")
                            .font(.headline)
                        Text(autoBackupURL.lastPathComponent)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                }
            }
        }
    }
    
    private func verificationSection(result: Result<BackupInfo, Error>) -> some View {
        Group {
            Divider()
            
            switch result {
            case .success(let info):
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(AppColors.success)
                        Text("Backup Verified Successfully")
                            .font(.headline)
                            .foregroundStyle(AppColors.success)
                    }
                    
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            InfoRow(label: "File Name", value: info.fileName)
                            InfoRow(label: "File Size", value: info.formattedFileSize)
                            InfoRow(label: "Created", value: DateFormatters.mediumDateTime.string(from: info.createdAt))
                            InfoRow(label: "Format Version", value: "\(info.formatVersion)")
                            InfoRow(label: "App Version", value: "\(info.appVersion) (\(info.appBuild))")
                            InfoRow(label: "Encrypted", value: info.isEncrypted ? "Yes" : "No")
                            InfoRow(label: "Compressed", value: info.isCompressed ? "Yes" : "No")
                            InfoRow(label: "Total Records", value: "\(info.totalEntityCount)")
                            InfoRow(label: "Checksum", value: String(info.checksum.prefix(16)) + "...")
                        }
                    }
                    
                    if !info.entityCounts.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Entity Counts")
                                    .font(.headline)
                                ForEach(
                                    Array(info.entityCounts.sorted(by: { $0.key < $1.key })),
                                    id: \.key
                                ) { key, count in
                                    HStack {
                                        Text(key)
                                            .font(.caption)
                                        Spacer()
                                        Text("\(count)")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                    }
                                }
                            }
                        }
                    }
                }
                
            case .failure(let error):
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(AppColors.destructive)
                        Text("Verification Failed")
                            .font(.headline)
                            .foregroundStyle(AppColors.destructive)
                    }
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private func loadBackupStatus() {
        Task { @MainActor in
            backupStatus = BackupVerification.getBackupStatus()
        }
    }
    
    private func verifyBackup(at url: URL) {
        isVerifying = true
        Task { @MainActor in
            verificationResult = BackupVerification.verifyBackup(at: url)
            isVerifying = false
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// DateFormatter extension moved to Utils/DateFormatters.swift for centralized management

#Preview {
    BackupStatusView()
}
