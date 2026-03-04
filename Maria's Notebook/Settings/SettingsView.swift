import SwiftUI
import SwiftData

// MARK: - SettingsView styled like the reference app, adapted to this app's data
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    // OPTIMIZATION: Use ViewModel for efficient statistics loading instead of loading entire tables
    @State private var statsViewModel = SettingsStatsViewModel()

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""

    private var overviewColumns: [GridItem] {
        // Fall back to single column at accessibility text sizes for readability
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
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
                        if matchesSearch("general school calendar display colors lesson age work age") {
                            generalSection
                        }
                        if matchesSearch("data sync icloud reminders calendar backup") {
                            dataSyncSection
                        }
                        if matchesSearch("backup restore data management export import") {
                            backupManagementSection
                        }
                        if matchesSearch("templates note meeting") {
                            templatesSection
                        }
                        if matchesSearch("communication attendance email") {
                            communicationSection
                        }
                        if matchesSearch("ai features claude api lesson planning assistant model apple on device") {
                            aiFeaturesSection
                        }
                        if matchesSearch("database statistics records overview storage") {
                            databaseSection
                        }
                        #if DEBUG
                        if matchesSearch("advanced debug test students") {
                            advancedSection
                        }
                        #endif
                    }
                    .frame(maxWidth: 900)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: .infinity)
                }
            }
            .searchable(text: $searchText, prompt: "Search settings")
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

    // MARK: - Search Filtering

    private func matchesSearch(_ keywords: String) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
        return keywords.lowercased().contains(query)
    }

    // MARK: - Section Definitions
    
    // 1. General
    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "General", systemImage: "gear")
            VStack(spacing: 12) {
                SettingsGroup(title: "School Calendar", systemImage: "calendar.badge.exclamationmark") {
                    SchoolCalendarSettingsView()
                        .frame(maxWidth: .infinity)
                }
                
                SettingsGroup(title: "Display & Colors", systemImage: "paintpalette.fill") {
                    VStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Lesson Age Indicators")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LessonAgeSettingsView()
                        }
                        
                        Divider()
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Work Age Indicators")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            WorkAgeSettingsView()
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // 2. Data & Sync
    private var dataSyncSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Data & Sync", systemImage: "arrow.triangle.2.circlepath")
            VStack(spacing: 12) {
                SettingsGroup(title: "iCloud", systemImage: "icloud.fill") {
                    VStack(spacing: 12) {
                        CloudKitStatusSettingsView()
                        
                        Divider()
                        
                        iCloudBackupToggle
                    }
                    .frame(maxWidth: .infinity)
                }
                
                SettingsGroup(title: "Reminders", systemImage: "bell.fill") {
                    ReminderSyncSettingsView()
                        .frame(maxWidth: .infinity)
                }
                
                SettingsGroup(title: "Calendar", systemImage: "calendar") {
                    CalendarSyncSettingsView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // 3. Backup & Data Management
    private var backupManagementSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Backup & Data Management", systemImage: "externaldrive.fill")
            DataManagementGrid()
        }
    }
    
    // 4. Templates
    private var templatesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Templates", systemImage: "doc.on.doc.fill")
            VStack(spacing: 12) {
                SettingsGroup(title: "Note Templates", systemImage: "note.text.badge.plus") {
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(statsViewModel.noteTemplatesCount)")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Templates Available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        
                        Divider()
                        
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
                
                SettingsGroup(title: "Meeting Templates", systemImage: "person.2.fill") {
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(statsViewModel.meetingTemplatesCount)")
                                    .font(.title2.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("Templates Available")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        
                        Divider()
                        
                        NavigationLink {
                            MeetingTemplateManagementView()
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
        }
    }
    
    // 5. Communication
    private var communicationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Communication", systemImage: "envelope.fill")
            SettingsGroup(title: "Attendance Email", systemImage: "checkmark.circle.fill") {
                AttendanceEmailSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
    
    // 6. AI Features
    private var aiFeaturesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "AI Features", systemImage: "brain.head.profile")
            VStack(spacing: 12) {
                SettingsGroup(title: "AI Models", systemImage: "cpu") {
                    AIModelSettingsView()
                        .frame(maxWidth: .infinity)
                }

                SettingsGroup(title: "Claude API Key", systemImage: "key.fill") {
                    VStack(spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Anthropic API")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                if AnthropicAPIClient.hasAPIKey() {
                                    Label("API key configured", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.success)
                                } else {
                                    Label("API key required for Claude models", systemImage: "exclamationmark.triangle")
                                        .font(.caption)
                                        .foregroundStyle(AppColors.warning)
                                }
                            }
                            Spacer()
                        }

                        Divider()

                        NavigationLink {
                            APIKeySettingsView()
                        } label: {
                            HStack {
                                Text("Configure API Key")
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                SettingsGroup(title: "Lesson Planning Assistant", systemImage: "list.clipboard") {
                    LessonPlanningSettingsView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
    
    // 7. Database
    private var databaseSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Database", systemImage: "cylinder.fill")
            SettingsGroup(title: "Database Overview", systemImage: "chart.bar.xaxis") {
                VStack(spacing: 16) {
                    // Total records summary at the top
                    DatabaseTotalSummary(totalRecords: statsViewModel.totalRecordsCount)

                    // MARK: Teaching
                    DatabaseStatsSubsection(
                        title: "Teaching",
                        systemImage: "book.fill",
                        summaryValue: "\(statsViewModel.studentsCount + statsViewModel.lessonsCount + statsViewModel.presentationsCount + statsViewModel.notesCount + statsViewModel.meetingsCount + statsViewModel.workModelsCount + statsViewModel.practiceSessionsCount) records"
                    ) {
                        LazyVGrid(columns: overviewColumns, spacing: 16) {
                            StatCard(title: "Students", value: "\(statsViewModel.studentsCount)", subtitle: nil, systemImage: "person.3.fill")
                            StatCard(title: "Lessons", value: "\(statsViewModel.lessonsCount)", subtitle: nil, systemImage: "text.book.closed.fill")
                            StatCard(title: "Lessons Planned", value: "\(statsViewModel.plannedCount)", subtitle: nil, systemImage: "books.vertical.fill")
                            StatCard(title: "Lessons Given", value: "\(statsViewModel.givenCount)", subtitle: nil, systemImage: "checkmark.circle.fill")
                            StatCard(title: "Work Items", value: "\(statsViewModel.workModelsCount)", subtitle: "Assigned", systemImage: "doc.text.fill")
                            StatCard(title: "Presentations", value: "\(statsViewModel.presentationsCount)", subtitle: "History", systemImage: "paintpalette.fill")
                            StatCard(title: "Observations", value: "\(statsViewModel.notesCount)", subtitle: "Notes", systemImage: "note.text")
                            StatCard(title: "Meetings", value: "\(statsViewModel.meetingsCount)", subtitle: "Records", systemImage: "person.2.fill")
                            StatCard(title: "Practice", value: "\(statsViewModel.practiceSessionsCount)", subtitle: "Sessions", systemImage: "music.note.list")
                        }
                    }

                    // MARK: Planning
                    DatabaseStatsSubsection(
                        title: "Planning",
                        systemImage: "checklist",
                        summaryValue: "\(statsViewModel.todoItemsCount + statsViewModel.remindersCount + statsViewModel.tracksCount + statsViewModel.calendarEventsCount + statsViewModel.projectsCount) records"
                    ) {
                        LazyVGrid(columns: overviewColumns, spacing: 16) {
                            StatCard(title: "To-Do Items", value: "\(statsViewModel.todoItemsCount)", subtitle: "\(statsViewModel.todoCompletedCount) completed", systemImage: "checklist")
                            StatCard(title: "Reminders", value: "\(statsViewModel.remindersCount)", subtitle: "Synced", systemImage: "bell.fill")
                            StatCard(title: "Tracks", value: "\(statsViewModel.tracksCount)", subtitle: "\(statsViewModel.trackEnrollmentsCount) enrollments", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            StatCard(title: "Calendar Events", value: "\(statsViewModel.calendarEventsCount)", subtitle: "Events", systemImage: "calendar")
                            StatCard(title: "Projects", value: "\(statsViewModel.projectsCount)", subtitle: nil, systemImage: "folder.fill")
                        }
                    }

                    // MARK: Classroom
                    DatabaseStatsSubsection(
                        title: "Classroom",
                        systemImage: "building.2.fill",
                        summaryValue: "\(statsViewModel.attendanceRecordsCount + statsViewModel.suppliesCount + statsViewModel.issuesCount + statsViewModel.communityTopicsCount + statsViewModel.proceduresCount + statsViewModel.nonSchoolDaysCount) records"
                    ) {
                        LazyVGrid(columns: overviewColumns, spacing: 16) {
                            StatCard(title: "Attendance", value: "\(statsViewModel.attendanceRecordsCount)", subtitle: "Records", systemImage: "checkmark.square.fill")
                            StatCard(title: "Supplies", value: "\(statsViewModel.suppliesCount)", subtitle: "Items", systemImage: "shippingbox.fill")
                            StatCard(title: "Issues", value: "\(statsViewModel.issuesCount)", subtitle: "\(statsViewModel.issuesResolvedCount) resolved", systemImage: "exclamationmark.triangle.fill")
                            StatCard(title: "Community", value: "\(statsViewModel.communityTopicsCount)", subtitle: "Topics", systemImage: "bubble.left.and.bubble.right.fill")
                            StatCard(title: "Procedures", value: "\(statsViewModel.proceduresCount)", subtitle: nil, systemImage: "list.clipboard.fill")
                            StatCard(title: "Non-School Days", value: "\(statsViewModel.nonSchoolDaysCount)", subtitle: "Configured", systemImage: "calendar.badge.minus")
                        }
                    }

                    // MARK: Storage
                    DatabaseStatsSubsection(
                        title: "Storage & Templates",
                        systemImage: "archivebox.fill",
                        summaryValue: "\(statsViewModel.documentsCount + statsViewModel.lessonAttachmentsCount + statsViewModel.communityAttachmentsCount + statsViewModel.noteTemplatesCount + statsViewModel.meetingTemplatesCount + statsViewModel.todoTemplatesCount + statsViewModel.developmentSnapshotsCount) records"
                    ) {
                        LazyVGrid(columns: overviewColumns, spacing: 16) {
                            StatCard(title: "Documents", value: "\(statsViewModel.documentsCount)", subtitle: "Files", systemImage: "doc.fill")
                            StatCard(title: "Lesson Files", value: "\(statsViewModel.lessonAttachmentsCount)", subtitle: "Attachments", systemImage: "paperclip")
                            StatCard(title: "Community Files", value: "\(statsViewModel.communityAttachmentsCount)", subtitle: "Attachments", systemImage: "paperclip.badge.ellipsis")
                            StatCard(title: "Note Templates", value: "\(statsViewModel.noteTemplatesCount)", subtitle: nil, systemImage: "note.text.badge.plus")
                            StatCard(title: "Meeting Templates", value: "\(statsViewModel.meetingTemplatesCount)", subtitle: nil, systemImage: "person.2.fill")
                            StatCard(title: "To-Do Templates", value: "\(statsViewModel.todoTemplatesCount)", subtitle: nil, systemImage: "checklist")
                            StatCard(title: "Dev Snapshots", value: "\(statsViewModel.developmentSnapshotsCount)", subtitle: "Analytics", systemImage: "camera.viewfinder")
                        }
                    }
                }
            }
        }
    }
    
    #if DEBUG
    // 7. Advanced (Debug Only)
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsCategoryHeader(title: "Advanced", systemImage: "wrench.and.screwdriver.fill")
            
            SettingsGroup(title: "Test Students", systemImage: "person.2.slash") {
                TestStudentsSettingsView()
                    .frame(maxWidth: .infinity)
            }
        }
    }
    #endif
    
    // iCloud Backup Toggle (extracted from DataManagementGrid)
    @AppStorage(UserDefaultsKeys.cloudBackupScheduleEnabled) private var cloudBackupEnabled = false
    
    private var iCloudBackupToggle: some View {
        SettingsToggleRow(
            title: "Enable iCloud Backup",
            systemImage: "icloud.and.arrow.up",
            color: .cyan,
            isOn: $cloudBackupEnabled
        )
    }
}

#Preview {
    SettingsView()
}
