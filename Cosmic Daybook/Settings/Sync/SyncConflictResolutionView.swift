import SwiftUI

// MARK: - Sync Problems View

/// "Sync problems": what has gone wrong with iCloud sync lately, and how two
/// devices' edits are settled. The notebook is Core Data mirrored to iCloud,
/// which keeps the most recent change to a record, so there is nothing to pick
/// between here; the real recovery is Troubleshooting › If sync gets stuck.
struct SyncConflictResolutionView: View {
    @Environment(\.dependencies) private var dependencies
    let logger = SyncEventLogger.shared

    private var recentErrors: [SyncEventLogger.SyncEvent] {
        logger.events.filter { $0.status == "error" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: SettingsStyle.sectionSpacing) {
                // Summary
                SettingsGroup(title: "Lately", systemImage: "arrow.triangle.2.circlepath") {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        HStack {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                                Text("\(logger.events.count)")
                                    .font(.title2.weight(.semibold))
                                Text("Recent sync activity")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: AppTheme.Spacing.xxsmall) {
                                Text("\(recentErrors.count)")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(
                                        recentErrors.isEmpty ? AppColors.success : AppColors.warning
                                    )
                                Text("Problems")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // How two devices' edits are settled
                SettingsGroup(
                    title: "When two devices change the same thing",
                    systemImage: "info.circle",
                    footer: "Changes usually reach your other devices within a few minutes "
                        + "when they're online, so try not to edit the same student or lesson "
                        + "on two devices at once."
                ) {
                    Text(
                        "Your notebook lives in iCloud. When the same record is changed on "
                        + "two devices, the most recent change wins."
                    )
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                }

                // Send now
                SettingsGroup(
                    title: "Still out of sync?",
                    systemImage: "wrench.fill",
                    footer: "If a device still looks out of date after a few minutes, open "
                        + "Troubleshooting › If sync gets stuck."
                ) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text("Send this device's latest changes to iCloud right away.")
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)

                        Button {
                            Task {
                                await dependencies.cloudKitSyncStatusService.syncNow()
                            }
                        } label: {
                            Label("Send changes now", systemImage: "arrow.up.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(dependencies.cloudKitSyncStatusService.isSyncing)
                    }
                }

                // Recent Errors
                if !recentErrors.isEmpty {
                    SettingsGroup(title: "Recent problems", systemImage: "exclamationmark.triangle") {
                        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                            ForEach(recentErrors.prefix(5)) { event in
                                HStack(alignment: .top, spacing: AppTheme.Spacing.small) {
                                    Circle()
                                        .fill(AppColors.destructive)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                                        Text(event.message)
                                            .font(.caption)
                                        Text(event.timestamp.formatted(.relative(presentation: .named)))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.compact)
        }
        .navigationTitle("Sync problems")
        .inlineNavigationTitle()
    }
}
