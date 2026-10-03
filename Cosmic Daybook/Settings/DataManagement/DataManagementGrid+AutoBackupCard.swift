import SwiftUI

extension DataManagementPanel {
    // MARK: - Auto-Backup Card

    var autoBackupCard: some View {
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
}
