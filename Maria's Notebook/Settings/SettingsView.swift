import SwiftUI
import SwiftData
#if DEBUG
import Foundation
#endif

// MARK: - SettingsView styled like the reference app, adapted to this app's data
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // Live data for stats
    @Query private var students: [Student]
    @Query private var lessons: [Lesson]
    @Query private var studentLessons: [StudentLesson]

    @Query(filter: #Predicate<StudentLesson> { $0.givenAt == nil })
    private var plannedLessons: [StudentLesson]

    @Query(filter: #Predicate<StudentLesson> { $0.givenAt != nil })
    private var givenLessons: [StudentLesson]
    
    @Query private var workContracts: [WorkContract]
    @Query private var presentations: [Presentation]
    @Query private var notes: [Note]
    @Query private var meetings: [StudentMeeting]

    private let overviewColumns: [GridItem] = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        NavigationStack {
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
                            studentsCount: studentsTotal,
                            lessonsCount: lessonsTotal,
                            plannedCount: plannedTotal,
                            givenCount: givenTotal,
                            columns: overviewColumns
                        )
                        
                        Divider()
                        
                        // Row 2: Detail (New)
                        LazyVGrid(columns: overviewColumns, spacing: 16) {
                            StatCard(title: "Work Items", value: "\(workContracts.count)", subtitle: "Assigned", systemImage: "doc.text.fill")
                            StatCard(title: "Presentations", value: "\(presentations.count)", subtitle: "History", systemImage: "easel.fill")
                            StatCard(title: "Observations", value: "\(notes.count)", subtitle: "Notes", systemImage: "note.text")
                            StatCard(title: "Meetings", value: "\(meetings.count)", subtitle: "Records", systemImage: "person.2.fill")
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
        }
        .onAppear {
            #if DEBUG
            PerformanceLogger.logScreenLoad(
                screenName: "SettingsView",
                itemCounts: [
                    "students": students.count,
                    "lessons": lessons.count,
                    "studentLessons": studentLessons.count,
                    "plannedLessons": plannedLessons.count,
                    "givenLessons": givenLessons.count
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
        }
    }

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
    
    private var iCloudStatusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "iCloud")
            SettingsGroup(title: "iCloud Status", systemImage: "icloud.fill") {
                CloudKitStatusSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var studentsTotal: Int { students.count }
    private var lessonsTotal: Int { lessons.count }
    private var plannedTotal: Int { plannedLessons.count }
    private var givenTotal: Int { givenLessons.count }
}

#Preview {
    SettingsView()
}

