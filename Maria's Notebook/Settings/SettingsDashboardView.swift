import SwiftUI

// MARK: - Settings Dashboard View

/// Overview dashboard shown when no settings category is selected.
/// Displays quick-status cards for iCloud sync, backup, AI, and templates.
struct SettingsDashboardView: View {
    @Environment(\.dependencies) private var dependencies
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    var statsViewModel: SettingsStatsViewModel

    private var columns: [GridItem] {
        let count = horizontalSizeClass == .regular ? 2 : 1
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: count)
    }

    var body: some View {
        VStack(spacing: SettingsStyle.sectionSpacing) {
            SettingsCategoryHeader(title: "Settings Overview", systemImage: "gear")

            WhatsNewBanner()

            LazyVGrid(columns: columns, spacing: 16) {
                syncStatusCard
                backupStatusCard
                aiModelCard
                templateCountsCard
            }
        }
    }

    // MARK: - Sync Status Card

    private var syncStatusCard: some View {
        let service = dependencies.cloudKitSyncStatusService
        return DashboardCard(
            title: "iCloud Sync",
            systemImage: service.syncHealth.icon,
            color: service.syncHealth.color
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(service.syncHealth.displayText)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(service.syncHealth.color)
                if let lastSync = service.lastSuccessfulSync {
                    Text("Last: \(lastSync, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Backup Status Card

    private var backupStatusCard: some View {
        let viewModel = SettingsViewModel(dependencies: dependencies)
        let lastDate = viewModel.lastBackupDate
        let daysSinceBackup: Int? = lastDate.map {
            Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0
        }
        let isOld = (daysSinceBackup ?? 999) >= 7

        return DashboardCard(
            title: "Backup",
            systemImage: isOld ? "exclamationmark.triangle.fill" : "externaldrive.fill",
            color: isOld ? AppColors.warning : AppColors.success
        ) {
            VStack(alignment: .leading, spacing: 4) {
                if let date = lastDate {
                    Text("\(date, style: .relative) ago")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isOld ? AppColors.warning : .primary)
                    if isOld {
                        Text("Consider creating a backup")
                            .font(.caption)
                            .foregroundStyle(AppColors.warning)
                    }
                } else {
                    Text("No backup found")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppColors.warning)
                    Text("Create your first backup")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - AI Model Card

    private var aiModelCard: some View {
        let hasKey = AnthropicAPIClient.hasAPIKey()
        let chatModel = AIFeatureArea.chat.resolvedModel()
        return DashboardCard(
            title: "AI Model",
            systemImage: "brain.head.profile",
            color: hasKey ? AppColors.info : AppColors.warning
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(chatModel.displayName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                if !hasKey && chatModel.requiresAPIKey {
                    Text("API key required")
                        .font(.caption)
                        .foregroundStyle(AppColors.warning)
                } else {
                    Text(chatModel.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Template Counts Card

    private var templateCountsCard: some View {
        let total = statsViewModel.noteTemplatesCount + statsViewModel.meetingTemplatesCount
            + statsViewModel.todoTemplatesCount
        return DashboardCard(
            title: "Templates",
            systemImage: "doc.on.doc.fill",
            color: .purple
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(total) templates")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Text(
                    "\(statsViewModel.noteTemplatesCount) note, "
                    + "\(statsViewModel.meetingTemplatesCount) meeting, "
                    + "\(statsViewModel.todoTemplatesCount) to-do"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Dashboard Card

private struct DashboardCard<Content: View>: View {
    let title: String
    let systemImage: String
    let color: Color
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            HStack(spacing: AppTheme.Spacing.small) {
                Image(systemName: systemImage)
                    .font(.subheadline)
                    .foregroundStyle(color)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
            }

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }
}
