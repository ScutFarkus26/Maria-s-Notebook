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

    @AppStorage("AutoBackup.enabled") private var autoBackupEnabled = true
    @AppStorage("AutoBackup.retentionCount") private var autoBackupRetention = 10
    @AppStorage("CloudBackup.scheduleEnabled") private var cloudBackupEnabled = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Data Management")
                .font(.title2)
                .fontWeight(.bold)

            // Progress/Result (inline, compact)
            if isShowingProgress {
                progressBar
            } else if let summary = resultSummary, !summary.isEmpty {
                resultBanner(summary)
            }

            // Compact 2x2 Grid
            LazyVGrid(columns: columns, spacing: 12) {
                backupCard
                restoreCard
                storageCard
                autoBackupCard
            }

            // iCloud row (always visible, compact)
            iCloudRow
        }
    }

    private var isShowingProgress: Bool {
        (backupProgress > 0 && backupProgress < 1.0) ||
        (importProgress > 0 && importProgress < 1.0)
    }

    // MARK: - Backup Card

    private var backupCard: some View {
        CompactCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Backup", systemImage: "externaldrive.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.blue)
                    Spacer()
                    encryptionPill
                }

                HStack {
                    if let size = estimatedBackupSize {
                        Text(formatByteCount(size))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Button {
                    performExport()
                } label: {
                    Text("Create Backup")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isShowingProgress)
            }
        }
    }

    private var encryptionPill: some View {
        Button {
            encryptBackups.toggle()
        } label: {
            HStack(spacing: 3) {
                Image(systemName: encryptBackups ? "lock.fill" : "lock.open")
                    .font(.caption2)
                Text(encryptBackups ? "Encrypted" : "Public")
                    .font(.caption2)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Restore Card

    private var restoreCard: some View {
        CompactCard {
            VStack(alignment: .leading, spacing: 10) {
                Label("Restore", systemImage: "arrow.counterclockwise")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.orange)

                Picker("", selection: $restoreMode) {
                    Text("Merge").tag(BackupService.RestoreMode.merge)
                    Text("Replace").tag(BackupService.RestoreMode.replace)
                }
                .pickerStyle(.segmented)
                .controlSize(.small)

                Button {
                    presentImporter()
                } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isShowingProgress)
            }
        }
    }

    // MARK: - Storage Card

    private var storageCard: some View {
        CompactCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Storage", systemImage: "folder.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.pink)
                    Spacer()
                    folderMenu
                }

                Text(defaultFolderName.isEmpty ? "No folder selected" : defaultFolderName)
                    .font(.caption)
                    .foregroundStyle(defaultFolderName.isEmpty ? .secondary : .primary)
                    .lineLimit(1)

                if let date = lastBackupDate {
                    Text("Last: \(formatRelativeTime(date))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var folderMenu: some View {
        Menu {
            Button { chooseDefaultFolder() } label: {
                Label("Choose Folder...", systemImage: "folder.badge.plus")
            }
            if !defaultFolderName.isEmpty {
                Button { openDefaultFolder() } label: {
                    Label("Open in Finder", systemImage: "arrow.up.forward.square")
                }
                Divider()
                Button(role: .destructive) { clearDefaultFolder() } label: {
                    Label("Clear", systemImage: "xmark.circle")
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
        CompactCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Auto-Backup", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.green)
                    Spacer()
                    Toggle("", isOn: $autoBackupEnabled)
                        .toggleStyle(.switch)
                        .scaleEffect(0.8)
                        .labelsHidden()
                }

                HStack {
                    Text("Keep")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Stepper(value: $autoBackupRetention, in: 1...100) {
                        Text("\(autoBackupRetention)")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    // MARK: - iCloud Row

    private var iCloudRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "icloud.fill")
                .foregroundColor(.cyan)
            Text("iCloud Backup")
                .font(.subheadline)
            Spacer()
            Toggle("", isOn: $cloudBackupEnabled)
                .toggleStyle(.switch)
                .scaleEffect(0.85)
                .labelsHidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        let (progress, _, color): (Double, String, Color) = backupProgress > 0
            ? (backupProgress, backupMessage, .blue)
            : (importProgress, importMessage, .green)

        return HStack(spacing: 10) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(color)
            Text("\(Int(progress * 100))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }

    // MARK: - Result Banner

    private func resultBanner(_ summary: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(summary)
                .font(.caption)
                .lineLimit(1)
            Spacer()
            Button { resultSummary = nil } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.green.opacity(0.12))
        )
    }

    // MARK: - Helpers

    private func formatByteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Compact Card

private struct CompactCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(cardBackground)
            )
    }

    private var cardBackground: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

// MARK: - Preview

#Preview {
    BackupRestoreSettingsView(
        encryptBackups: .constant(false),
        restoreMode: .constant(.merge),
        backupProgress: .constant(0),
        backupMessage: .constant(""),
        importProgress: .constant(0),
        importMessage: .constant(""),
        resultSummary: .constant(nil),
        defaultFolderName: .constant("Maria's Notebook Backups"),
        lastBackupDate: Date().addingTimeInterval(-3600),
        estimatedBackupSize: 1_200_000,
        performExport: {},
        presentImporter: {},
        chooseDefaultFolder: {},
        openDefaultFolder: {},
        clearDefaultFolder: {}
    )
    .padding()
    .frame(width: 500, height: 320)
    .preferredColorScheme(.dark)
}
