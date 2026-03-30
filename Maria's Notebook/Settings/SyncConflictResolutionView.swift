import SwiftUI

// MARK: - Sync Conflict Resolution View

/// Informational view about sync conflicts and resolution.
/// SwiftData with CloudKit uses last-writer-wins, so this is primarily informational.
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
                SettingsGroup(title: "Sync Overview", systemImage: "arrow.triangle.2.circlepath") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(logger.events.count)")
                                    .font(.title2.weight(.semibold))
                                Text("Total sync events")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(recentErrors.count)")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(
                                        recentErrors.isEmpty ? AppColors.success : AppColors.warning
                                    )
                                Text("Errors")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                // How Conflicts Work
                SettingsGroup(title: "How Conflicts are Resolved", systemImage: "info.circle") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            "Maria's Notebook uses iCloud with SwiftData for syncing. "
                            + "When the same record is edited on multiple devices, "
                            + "the most recent change wins automatically."
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(
                            "This means you should avoid editing the same student, lesson, "
                            + "or record on two devices simultaneously. "
                            + "Changes sync within a few minutes when connected."
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Force Re-Sync
                SettingsGroup(title: "Troubleshooting", systemImage: "wrench.fill") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("If data appears out of sync, try forcing a full re-sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            Task {
                                await dependencies.cloudKitSyncStatusService.syncNow()
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Force Full Re-Sync")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }

                // Recent Errors
                if !recentErrors.isEmpty {
                    SettingsGroup(title: "Recent Errors", systemImage: "exclamationmark.triangle") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(recentErrors.prefix(5)) { event in
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(AppColors.destructive)
                                        .frame(width: 6, height: 6)
                                        .padding(.top, 5)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(event.message)
                                            .font(.caption)
                                        Text(event.timestamp, style: .relative)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .navigationTitle("Sync Details")
        .inlineNavigationTitle()
    }
}
