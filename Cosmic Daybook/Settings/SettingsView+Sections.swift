import SwiftUI

// MARK: - SettingsView Panes

extension SettingsView {

    /// One pane per sidebar category. Each card's name comes from `SettingsCopy.Group`.
    @ViewBuilder
    func settingsPaneContent(for category: SettingsCategory) -> some View {
        switch category {
        case .overview:
            SettingsDashboardView(statsViewModel: statsViewModel, onOpen: openCategory, onOpenCard: openCard)
        case .schoolYear:
            schoolYearPane
        case .classroom:
            ClassroomSharingView()
                .settingsAnchor(.classroomSharing)
        case .lookAndFeel:
            lookAndFeelPane
        case .messages:
            messagesPane
        case .templates:
            SettingsTemplatesPane(statsViewModel: statsViewModel)
        case .connections:
            connectionsPane
        case .intelligence:
            SettingsIntelligencePane()
        case .syncBackup:
            syncBackupPane
        case .troubleshooting:
            troubleshootingPane
        }
    }

    // MARK: - School Year

    private var schoolYearPane: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            SettingsGroup(.schoolYearStart) {
                SchoolYearStartSettingsView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsGroup(
                .daysOff,
                footer: "Planning and attendance skip days off. They're shared with your assistant, " +
                    "so attendance skips them there too."
            ) {
                SchoolCalendarSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(.newYear) {
                NewSchoolYearSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Look and Feel

    private var lookAndFeelPane: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            AgeIndicatorsSettingsGroup()

            QuickCaptureButtonSettingsView()
        }
    }

    // MARK: - Messages

    private var messagesPane: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            SettingsGroup(.attendanceEmail) {
                AttendanceEmailSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(.parentReports) {
                ParentReportsSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(.orderRequests) {
                OrderRequestSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Connections

    private var connectionsPane: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            SettingsGroup(.appleCalendar, collapsible: true) {
                CalendarSyncSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(.reminders, collapsible: true) {
                ReminderSyncSettingsView()
                    .frame(maxWidth: .infinity)
            }

            #if os(macOS)
            SettingsGroup(.claudeDesktop) {
                ClaudeDesktopSettingsView()
                    .frame(maxWidth: .infinity)
            }
            #endif
        }
    }

    // MARK: - Sync and Backup

    private var syncBackupPane: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            SettingsGroup(.iCloud) {
                CloudKitStatusSettingsView()
                    .frame(maxWidth: .infinity)
            }

            DataManagementGrid()
                .settingsAnchor(.backups)

            SettingsTransferView()
        }
    }

    // MARK: - Troubleshooting

    private var troubleshootingPane: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            SettingsGroup(.syncHistory) {
                VStack(spacing: 0) {
                    NavigationLink {
                        SyncHistoryLogView(logger: SyncEventLogger.shared)
                            .settingsBreadcrumb("Settings › Troubleshooting")
                    } label: {
                        SettingsLinkRow(title: "Sync history", systemImage: "clock.arrow.circlepath")
                    }
                    .buttonStyle(.plain)

                    Divider()

                    NavigationLink {
                        SyncConflictResolutionView()
                            .settingsBreadcrumb("Settings › Troubleshooting")
                    } label: {
                        SettingsLinkRow(title: "Sync problems", systemImage: "exclamationmark.triangle")
                    }
                    .buttonStyle(.plain)
                }
            }

            DatabaseMaintenanceCard()

            #if os(macOS)
            NotebookCleanupCard()
            #endif

            SettingsNotebookStatsView(statsViewModel: statsViewModel)

            #if DEBUG
            SettingsGroup(.testStudents) {
                TestStudentsSettingsView()
                    .frame(maxWidth: .infinity)
            }
            #endif
        }
    }
}
