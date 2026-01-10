import SwiftUI
import SwiftData
#if DEBUG
import Foundation
#endif

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
        // FIX: Removed NavigationStack wrapper. This view is presented within an existing
        // NavigationStack (More Menu) or NavigationSplitView Detail (iPad), so it should
        // not create its own stack.
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - School Configuration Section
                schoolConfigurationSection
                
                // MARK: - Students Section
                studentsSection
                
                // MARK: - Attendance Section
                attendanceSection
                
                // MARK: - Reminders Section
                remindersSection
                
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
                        StatCard(title: "Work Items", value: "\(statsViewModel.workContractsCount)", subtitle: "Assigned", systemImage: "doc.text.fill")
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
        .navigationTitle("Settings")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            // OPTIMIZATION: Load statistics efficiently via ViewModel
            statsViewModel.loadCounts(context: modelContext)
            
            #if DEBUG
            PerformanceLogger.logScreenLoad(
                screenName: "SettingsView",
                itemCounts: [
                    "students": statsViewModel.studentsCount,
                    "lessons": statsViewModel.lessonsCount,
                    "studentLessons": statsViewModel.studentLessonsCount,
                    "plannedLessons": statsViewModel.plannedCount,
                    "givenLessons": statsViewModel.givenCount
                ]
            )
            #endif
            // If we are no longer in an ephemeral session (i.e., persistent container opened), clear any stale message.
            if !UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag) {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
            }
        }
    }

    // Extracted sections to reduce type-checker complexity
    private var studentsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Students")
            SettingsGroup(title: "Test Students", systemImage: "person.2.slash") {
                TestStudentsSettingsView()
                    .frame(maxWidth: .infinity)
            }
            SettingsGroup(title: "Curriculum Tracks", systemImage: "list.number") {
                NavigationLink(destination: TrackListView()) {
                    HStack {
                        Text("Manage Tracks")
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
            SettingsGroup(title: "Progress Sync", systemImage: "arrow.triangle.2.circlepath") {
                ProgressSyncSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Data Management")
            DataManagementGrid()
            SettingsGroup(title: "Note Migration", systemImage: "arrow.triangle.2.circlepath") {
                NoteMigrationSettingsCard()
            }
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

