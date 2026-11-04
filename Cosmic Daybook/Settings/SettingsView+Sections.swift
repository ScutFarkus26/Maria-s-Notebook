import SwiftUI

// MARK: - SettingsView Panes

extension SettingsView {

    /// One pane per sidebar category. Each card's name comes from `SettingsCopy.Group`.
    @ViewBuilder
    func settingsPaneContent(for category: SettingsCategory) -> some View {
        switch category {
        case .schoolYear:
            schoolYearPane
        case .classroom:
            ClassroomSharingView()
                .settingsAnchor(.classroomSharing)
        case .lookAndFeel:
            lookAndFeelPane
        case .templates:
            SettingsTemplatesPane()
        case .intelligence:
            SettingsIntelligencePane()
        case .syncBackup:
            syncBackupPane
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

    /// How the notebook looks, then the messages it sends.
    private var lookAndFeelPane: some View {
        VStack(spacing: SettingsStyle.groupSpacing) {
            AgeIndicatorsSettingsGroup()

            QuickCaptureButtonSettingsView()

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

            repairCards
        }
    }

    /// Sync history and the repairs, below the everyday cards.
    @ViewBuilder
    private var repairCards: some View {
        SettingsGroup(.syncHistory) {
            VStack(spacing: 0) {
                NavigationLink {
                    SyncHistoryLogView(logger: SyncEventLogger.shared)
                        .settingsBreadcrumb("Settings › Sync and backup")
                } label: {
                    SettingsLinkRow(title: "Sync history", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.plain)

                Divider()

                NavigationLink {
                    SyncConflictResolutionView()
                        .settingsBreadcrumb("Settings › Sync and backup")
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

        #if DEBUG
        SettingsGroup(.testStudents) {
            TestStudentsSettingsView()
                .frame(maxWidth: .infinity)
        }
        #endif
    }
}
