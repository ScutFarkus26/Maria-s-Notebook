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

    #if DEBUG
    @State private var showTrackPopulator = false
    @State private var isRunningRepair = false
    @State private var repairMessage: String?
    @State private var showOrphanedWorkDiagnostic = false
    @State private var orphanedWorkResult: OrphanedWorkDiagnostic.DiagnosticResult?
    @State private var lessonSearchText = ""
    @State private var lessonSearchResults: [Lesson] = []
    #endif

    private var overviewColumns: [GridItem] {
        // Use 2 columns on iPhone (compact), 4 columns on iPad (regular)
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    var body: some View {
        // FIX: Removed NavigationStack wrapper. This view is presented within an existing
        // NavigationStack (More Menu) or NavigationSplitView Detail (iPad), so it should
        // not create its own stack.
        VStack(spacing: 0) {
            ViewHeader(title: "Settings")
            Divider()
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

                    #if DEBUG
                    // MARK: - Debug Section
                    debugSection
                    #endif
                }
                .frame(maxWidth: 900)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
            }
        }
        #if DEBUG
        .sheet(isPresented: $showTrackPopulator) {
            NavigationStack {
                TrackPopulationView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") {
                                showTrackPopulator = false
                            }
                        }
                    }
            }
        }
        #endif
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
            #if DEBUG
            SettingsGroup(title: "Test Students", systemImage: "person.2.slash") {
                TestStudentsSettingsView()
                    .frame(maxWidth: .infinity)
            }
            #endif
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
    
    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Debug")
            SettingsGroup(title: "Track Population", systemImage: "list.number") {
                Button(action: {
                    showTrackPopulator = true
                }) {
                    HStack {
                        Text("Populate Tracks from History")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            SettingsGroup(title: "Presentation Links Repair", systemImage: "link.badge.plus") {
                VStack(alignment: .leading, spacing: 8) {
                    Button(action: {
                        runPresentationRepair()
                    }) {
                        HStack {
                            if isRunningRepair {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text("Run Presentation StudentLesson Link Repair")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunningRepair)

                    if let message = repairMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            SettingsGroup(title: "Orphaned Work Diagnostic", systemImage: "exclamationmark.triangle") {
                VStack(alignment: .leading, spacing: 12) {
                    Button(action: {
                        orphanedWorkResult = OrphanedWorkDiagnostic.run(context: modelContext)
                        showOrphanedWorkDiagnostic = true
                        // Also print to console for detailed view
                        OrphanedWorkDiagnostic.printReport(context: modelContext)
                    }) {
                        HStack {
                            Text("Run Orphaned Work Diagnostic")
                            Spacer()
                        }
                    }
                    .buttonStyle(.bordered)

                    if showOrphanedWorkDiagnostic, let result = orphanedWorkResult {
                        Divider()
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Total Work Items: \(result.totalWorkItems)")
                            Text("Valid Lesson Links: \(result.workItemsWithValidLessons)")
                            Text("Orphaned (missing lesson): \(result.orphanedWorkItems)")
                                .foregroundStyle(result.orphanedWorkItems > 0 ? .red : .green)
                            Text("Existing Lessons: \(result.existingLessons)")
                        }
                        .font(.caption)

                        if !result.missingLessonIDs.isEmpty {
                            Divider()
                            Text("Missing Lesson IDs:")
                                .font(.caption.bold())
                            ForEach(Array(result.missingLessonIDs.keys.sorted()), id: \.self) { lessonID in
                                let count = result.missingLessonIDs[lessonID] ?? 0
                                let shortID = String(lessonID.prefix(6)).uppercased()
                                Text("  Lesson \(shortID): \(count) work item(s)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Divider()

                    Text("Search Lessons")
                        .font(.caption.bold())
                    HStack {
                        TextField("Search (e.g., geometry)", text: $lessonSearchText)
                            .textFieldStyle(.roundedBorder)
                        Button("Search") {
                            lessonSearchResults = OrphanedWorkDiagnostic.searchLessons(
                                matching: lessonSearchText,
                                context: modelContext
                            )
                            // Also print to console
                            OrphanedWorkDiagnostic.printLessonSearch(matching: lessonSearchText, context: modelContext)
                        }
                        .buttonStyle(.bordered)
                        .disabled(lessonSearchText.isEmpty)
                    }

                    if !lessonSearchResults.isEmpty {
                        Text("Found \(lessonSearchResults.count) lesson(s):")
                            .font(.caption)
                        ForEach(lessonSearchResults.prefix(10)) { lesson in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(lesson.name)
                                    .font(.caption.bold())
                                Text("Subject: \(lesson.subject.isEmpty ? "(none)" : lesson.subject), Group: \(lesson.group.isEmpty ? "(none)" : lesson.group)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if lessonSearchResults.count > 10 {
                            Text("... and \(lessonSearchResults.count - 10) more (see console)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if !lessonSearchText.isEmpty && lessonSearchResults.isEmpty {
                        Text("No lessons found matching '\(lessonSearchText)'")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("List All Subjects") {
                        OrphanedWorkDiagnostic.printSubjects(context: modelContext)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
        }
    }
    #endif

    #if DEBUG
    private func runPresentationRepair() {
        guard !isRunningRepair else { return }
        isRunningRepair = true
        repairMessage = "Running repair..."
        
        Task { @MainActor in
            // Reset the migration flag to allow re-running
            MigrationFlag.reset(key: "Repair.presentationStudentLessonLinks.v2")
            
            // Run the repair
            await DataMigrations.repairPresentationStudentLessonLinks_v2(using: modelContext)
            
            isRunningRepair = false
            repairMessage = "Repair completed. Check console for details."
            
            // Clear message after 5 seconds
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                repairMessage = nil
            }
        }
    }
    #endif

}

#Preview {
    SettingsView()
}
