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

    // Cloud backup settings
    @AppStorage("CloudBackup.scheduleEnabled") private var cloudBackupEnabled = false

    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Section Title
            Text("Data Management")
                .font(.title2)
                .fontWeight(.bold)

            // Progress indicator (shown when active)
            if isShowingProgress {
                progressOverlay
            }

            // Result banner (dismissible)
            if let summary = resultSummary, !summary.isEmpty {
                resultBanner(summary)
            }

            // Main 2x2 Grid
            LazyVGrid(columns: columns, spacing: 16) {
                // Backup Card
                backupCard

                // Restore Card
                restoreCard

                // Storage Card
                storageCard

                // Auto-Backup Card
                autoBackupCard
            }

            // Cloud Backup Card (full width, optional)
            if cloudBackupEnabled {
                cloudBackupCard
            }
        }
    }

    private var isShowingProgress: Bool {
        (backupProgress > 0 && backupProgress < 1.0) ||
        (importProgress > 0 && importProgress < 1.0)
    }

    // MARK: - Backup Card

    private var backupCard: some View {
        DataManagementCard {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                CardHeader(title: "Backup", icon: "externaldrive.fill", color: .blue)

                Spacer()

                // Size and encryption status
                HStack {
                    if let size = estimatedBackupSize {
                        Text(formatByteCount(size))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Encryption toggle pill
                    Button {
                        encryptBackups.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: encryptBackups ? "lock.fill" : "lock.open")
                                .font(.caption2)
                            Text(encryptBackups ? "Encrypted" : "Public")
                                .font(.caption)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.primary.opacity(0.1))
                        )
                    }
                    .buttonStyle(.plain)
                }

                // Create Backup Button
                Button {
                    performExport()
                } label: {
                    Text("Create Backup")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isShowingProgress)
            }
        }
    }

    // MARK: - Restore Card

    private var restoreCard: some View {
        DataManagementCard {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                CardHeader(title: "Restore", icon: "arrow.counterclockwise", color: .orange)

                Spacer()

                // Mode Picker
                Picker("Mode", selection: $restoreMode) {
                    Text("Merge").tag(BackupService.RestoreMode.merge)
                    Text("Replace").tag(BackupService.RestoreMode.replace)
                }
                .pickerStyle(.segmented)

                // Checksum bypass toggle
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Skip Checksum Validation")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { UserDefaults.standard.bool(forKey: UserDefaultsKeys.backupAllowChecksumBypass) },
                        set: { UserDefaults.standard.set($0, forKey: UserDefaultsKeys.backupAllowChecksumBypass) }
                    ))
                    .toggleStyle(.switch)
                    .scaleEffect(0.8)
                    .labelsHidden()
                }

                // Import Button
                Button {
                    presentImporter()
                } label: {
                    Label("Import File...", systemImage: "square.and.arrow.down")
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                .disabled(isShowingProgress)
            }
        }
    }

    // MARK: - Storage Card

    private var storageCard: some View {
        DataManagementCard {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                CardHeader(title: "Storage", icon: "folder.fill", color: .pink)

                Spacer()

                // Folder name
                if !defaultFolderName.isEmpty {
                    Text(defaultFolderName)
                        .font(.subheadline)
                        .lineLimit(2)
                        .foregroundStyle(.primary)
                } else {
                    Text("No folder selected")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Last backup time and menu
                HStack {
                    if let date = lastBackupDate {
                        Text("Last: \(formatRelativeTime(date))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Menu {
                        Button {
                            chooseDefaultFolder()
                        } label: {
                            Label("Choose Folder...", systemImage: "folder.badge.plus")
                        }

                        if !defaultFolderName.isEmpty {
                            Button {
                                openDefaultFolder()
                            } label: {
                                Label("Open in Finder", systemImage: "arrow.up.forward.square")
                            }

                            Divider()

                            Button(role: .destructive) {
                                clearDefaultFolder()
                            } label: {
                                Label("Clear Folder", systemImage: "xmark.circle")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
    }

    // MARK: - Auto-Backup Card

    private var autoBackupCard: some View {
        DataManagementCard {
            VStack(alignment: .leading, spacing: 12) {
                // Header
                CardHeader(title: "Auto-Backup", icon: "clock.arrow.circlepath", color: .blue)

                Spacer()

                // On Quit toggle
                HStack {
                    Text("On Quit")
                        .font(.subheadline)
                    Spacer()
                    Toggle("", isOn: $autoBackupEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                // Retention stepper
                HStack {
                    Text("Keep recent:")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Stepper(value: $autoBackupRetention, in: 1...100, step: 1) {
                        Text("\(autoBackupRetention)")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    // MARK: - Cloud Backup Card (Full Width)

    private var cloudBackupCard: some View {
        DataManagementCard {
            HStack(spacing: 16) {
                // Icon
                Image(systemName: "icloud.fill")
                    .font(.title2)
                    .foregroundColor(.cyan)

                VStack(alignment: .leading, spacing: 4) {
                    Text("iCloud Backup")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Syncing enabled")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Toggle("", isOn: $cloudBackupEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        }
    }

    // MARK: - Progress Overlay

    private var progressOverlay: some View {
        VStack(spacing: 8) {
            if backupProgress > 0 && backupProgress < 1.0 {
                ProgressRow(
                    title: "Exporting...",
                    message: backupMessage,
                    progress: backupProgress,
                    color: .blue
                )
            }

            if importProgress > 0 && importProgress < 1.0 {
                ProgressRow(
                    title: "Importing...",
                    message: importMessage,
                    progress: importProgress,
                    color: .green
                )
            }
        }
    }

    // MARK: - Result Banner

    private func resultBanner(_ summary: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text(summary)
                .font(.subheadline)
            Spacer()
            Button {
                resultSummary = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.green.opacity(0.15))
        )
    }

    // MARK: - Helpers

    private func formatByteCount(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Supporting Views

private struct DataManagementCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 160, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(cardBackgroundColor)
            )
    }

    private var cardBackgroundColor: Color {
        #if os(macOS)
        Color(nsColor: .controlBackgroundColor)
        #else
        Color(uiColor: .secondarySystemBackground)
        #endif
    }
}

private struct CardHeader: View {
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

private struct ProgressRow: View {
    let title: String
    let message: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(color)

            if !message.isEmpty {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        BackupRestoreSettingsView(
            encryptBackups: .constant(false),
            restoreMode: .constant(.merge),
            backupProgress: .constant(0),
            backupMessage: .constant(""),
            importProgress: .constant(0),
            importMessage: .constant(""),
            resultSummary: .constant(nil),
            defaultFolderName: .constant("Maria's Notebook New Backups"),
            lastBackupDate: Date().addingTimeInterval(-82),
            estimatedBackupSize: 1_200_000,
            performExport: {},
            presentImporter: {},
            chooseDefaultFolder: {},
            openDefaultFolder: {},
            clearDefaultFolder: {}
        )
        .padding()
    }
    .frame(width: 700, height: 500)
    .preferredColorScheme(.dark)
}
