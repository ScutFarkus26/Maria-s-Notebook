import SwiftUI
import SwiftData

// MARK: - SettingsView styled like the reference app, adapted to this app's data
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // OPTIMIZATION: Use ViewModel for efficient statistics loading instead of loading entire tables
    @StateObject private var statsViewModel = SettingsStatsViewModel()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var overviewColumns: [GridItem] {
        // Use 2 columns on iPhone (compact), 4 columns on iPad (regular)
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    var body: some View {
        // NavigationStack is needed for NavigationLink destinations (e.g., NoteTemplateManagementView)
        // to work correctly when SettingsView is displayed in a NavigationSplitView detail pane.
        NavigationStack {
            VStack(spacing: 0) {
                ViewHeader(title: "Settings")
                Divider()
                ScrollView {
                    VStack(spacing: 24) {
                        // MARK: - School Configuration Section
                        schoolConfigurationSection

                        #if DEBUG
                        // MARK: - Students Section
                        studentsSection
                        #endif

                        // MARK: - Attendance Section
                        attendanceSection

                        // MARK: - Reminders Section
                        remindersSection

                        // MARK: - Calendar Section
                        calendarSection

                        // MARK: - Notes Section
                        notesSection

                        // MARK: - Data Management Section
                        dataManagementSection

                        // MARK: - Overview Section
                        SettingsGroup(title: "Database Overview", systemImage: "chart.bar.xaxis") {
                            // Row 1: Core (Existing)
                            OverviewStatsGrid(
                                studentsCount: statsViewModel.studentsCount,
                                lessonsCount: statsViewModel.lessonsCount,
                                plannedCount: statsViewModel.plannedCount,
                                givenCount: statsViewModel.givenCount,
                                columns: overviewColumns
                            )

                            Divider()

                            // Row 2: Detail (New)
                            LazyVGrid(columns: overviewColumns, spacing: 16) {
                                StatCard(title: "Work Items", value: "\(statsViewModel.workModelsCount)", subtitle: "Assigned", systemImage: "doc.text.fill")
                                StatCard(title: "Presentations", value: "\(statsViewModel.presentationsCount)", subtitle: "History", systemImage: "paintpalette.fill")
                                StatCard(title: "Observations", value: "\(statsViewModel.notesCount)", subtitle: "Notes", systemImage: "note.text")
                                StatCard(title: "Meetings", value: "\(statsViewModel.meetingsCount)", subtitle: "Records", systemImage: "person.2.fill")
                            }
                        }

                        // MARK: - iCloud Status Section
                        iCloudStatusSection
                    }
                    .frame(maxWidth: 900)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
            }
        }
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            // OPTIMIZATION: Load statistics efficiently via ViewModel
            statsViewModel.loadCounts(context: modelContext)

            // If we are no longer in an ephemeral session (i.e., persistent container opened), clear any stale message.
            if !UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag) {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
            }
        }
    }

    // Extracted sections to reduce type-checker complexity
    #if DEBUG
    private var studentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Students")
            SettingsGroup(title: "Test Students", systemImage: "person.2.slash") {
                TestStudentsSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
    #endif

    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Data Management")
            DataManagementGrid()
        }
    }

    private var schoolConfigurationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "School Configuration")
            SettingsGroup(title: "School Calendar", systemImage: "calendar.badge.exclamationmark") {
                SchoolCalendarSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var attendanceSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Attendance")
            SettingsGroup(title: "Attendance Email", systemImage: "envelope") {
                AttendanceEmailSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Reminders")
            SettingsGroup(title: "Reminder Sync", systemImage: "bell.fill") {
                ReminderSyncSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Calendar")
            SettingsGroup(title: "Calendar Sync", systemImage: "calendar") {
                CalendarSyncSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Notes")
            SettingsGroup(title: "Note Templates", systemImage: "note.text.badge.plus") {
                NavigationLink {
                    NoteTemplateManagementView()
                } label: {
                    HStack {
                        Text("Manage Templates")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var iCloudStatusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "iCloud")
            SettingsGroup(title: "iCloud Status", systemImage: "icloud.fill") {
                CloudKitStatusSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

#Preview {
    SettingsView()
}
