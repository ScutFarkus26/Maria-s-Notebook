import SwiftUI
import SwiftData

// MARK: - Settings Category

enum SettingsCategory: String, CaseIterable, Identifiable, Hashable {
    case general
    case dataSync
    case backup
    case templates
    case communication
    case aiFeatures
    case database
    case advanced // Only shown in DEBUG builds

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .general: return "General"
        case .dataSync: return "Data & Sync"
        case .backup: return "Backup"
        case .templates: return "Templates"
        case .communication: return "Communication"
        case .aiFeatures: return "AI & Models"
        case .database: return "Database"
        case .advanced: return "Advanced"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gear"
        case .dataSync: return "arrow.triangle.2.circlepath"
        case .backup: return "externaldrive.fill"
        case .templates: return "doc.on.doc.fill"
        case .communication: return "envelope.fill"
        case .aiFeatures: return "brain.head.profile"
        case .database: return "cylinder.fill"
        case .advanced: return "wrench.and.screwdriver.fill"
        }
    }

    var searchKeywords: String {
        switch self {
        case .general: return "general school calendar display colors lesson age work age"
        case .dataSync: return "data sync icloud reminders calendar"
        case .backup: return "backup restore data management export import"
        case .templates: return "templates note meeting"
        case .communication: return "communication attendance email"
        case .aiFeatures: return "ai features claude api lesson planning assistant model apple on device ollama mlx models download local"
        case .database: return "database statistics records overview storage"
        case .advanced: return "advanced debug test students"
        }
    }

    /// Categories visible in the UI (excludes advanced in release builds)
    static var visibleCategories: [SettingsCategory] {
        #if DEBUG
        return allCases
        #else
        return allCases.filter { $0 != .advanced }
        #endif
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var statsViewModel = SettingsStatsViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var searchText = ""
    @AppStorage("settings_selectedCategory") private var selectedCategoryRaw: String = SettingsCategory.general.rawValue

    private var isCompact: Bool {
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    private var selectedCategory: SettingsCategory {
        get { SettingsCategory(rawValue: selectedCategoryRaw) ?? .general }
    }

    private var selectedCategoryBinding: Binding<SettingsCategory?> {
        Binding<SettingsCategory?>(
            get: { SettingsCategory(rawValue: selectedCategoryRaw) ?? .general },
            set: { if let cat = $0 { selectedCategoryRaw = cat.rawValue } }
        )
    }

    private var filteredCategories: [SettingsCategory] {
        let visible = SettingsCategory.visibleCategories
        guard !searchText.isEmpty else { return visible }
        let query = searchText.lowercased()
        return visible.filter {
            $0.searchKeywords.lowercased().contains(query) ||
            $0.displayName.lowercased().contains(query)
        }
    }

    private var overviewColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        let columnCount = horizontalSizeClass == .regular ? 4 : 2
        return Array(repeating: GridItem(.flexible(), spacing: 16), count: columnCount)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ViewHeader(title: "Settings")
                Divider()
                settingsContent
            }
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            statsViewModel.loadCounts(context: modelContext)

            if !UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag) {
                UserDefaults.standard.removeObject(forKey: UserDefaultsKeys.lastStoreErrorDescription)
            }
        }
    }

    // MARK: - Layout Switching

    @ViewBuilder
    private var settingsContent: some View {
        if isCompact {
            compactSettingsList
        } else {
            wideSettingsLayout
        }
    }

    // MARK: - Wide Layout (Mac / iPad)

    private var wideSettingsLayout: some View {
        HStack(spacing: 0) {
            settingsSidebar
                .frame(width: 200)
            Divider()
            settingsDetailPane
        }
    }

    private var settingsSidebar: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Search", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List(filteredCategories, selection: selectedCategoryBinding) { category in
                Label(category.displayName, systemImage: category.icon)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .background(SettingsStyle.groupBackgroundColor.opacity(0.5))
    }

    private var settingsDetailPane: some View {
        ScrollView {
            settingsPaneContent(for: selectedCategory)
                .frame(maxWidth: 700)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
        }
        .id(selectedCategory) // Reset scroll position when switching categories
    }

    // MARK: - Compact Layout (iPhone)

    private var compactSettingsList: some View {
        List {
            ForEach(filteredCategories) { category in
                NavigationLink(value: category) {
                    Label(category.displayName, systemImage: category.icon)
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search settings")
        .navigationDestination(for: SettingsCategory.self) { category in
            ScrollView {
                settingsPaneContent(for: category)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .navigationTitle(category.displayName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.large)
            #endif
        }
    }

    // MARK: - Pane Content Router

    @ViewBuilder
    private func settingsPaneContent(for category: SettingsCategory) -> some View {
        switch category {
        case .general:
            generalSection
        case .dataSync:
            dataSyncSection
        case .backup:
            backupManagementSection
        case .templates:
            templatesSection
        case .communication:
            communicationSection
        case .aiFeatures:
            aiFeaturesSection
        case .database:
            databaseSection
        case .advanced:
            advancedSection
        }
    }

    // MARK: - Section Definitions

    // 1. General
    private var generalSection: some View {
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

    // 2. Data & Sync
    private var dataSyncSection: some View {
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

    // 3. Backup & Data Management
    private var backupManagementSection: some View {
        DataManagementGrid()
    }

    // 4. Templates
    private var templatesSection: some View {
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

    // 5. Communication
    private var communicationSection: some View {
        SettingsGroup(title: "Attendance Email", systemImage: "checkmark.circle.fill") {
            AttendanceEmailSettingsView()
                .frame(maxWidth: .infinity)
        }
    }

    // 6. AI Features
    private var aiFeaturesSection: some View {
        VStack(spacing: 12) {
            SettingsGroup(title: "AI Models", systemImage: "cpu") {
                AIModelSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(title: "Apple Intelligence", systemImage: "apple.logo") {
                appleIntelligenceStatus
            }

            SettingsGroup(title: "MLX Models", systemImage: "cpu") {
                MLXModelSettingsView()
                    .frame(maxWidth: .infinity)
            }

            SettingsGroup(title: "Ollama", systemImage: "server.rack") {
                OllamaSettingsView()
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

    // 7. Database
    private var databaseSection: some View {
        SettingsGroup(title: "Database Overview", systemImage: "chart.bar.xaxis") {
            VStack(spacing: 16) {
                DatabaseTotalSummary(totalRecords: statsViewModel.totalRecordsCount)

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

    // 8. Advanced (Debug Only — hidden in release via visibleCategories filter)
    private var advancedSection: some View {
        SettingsGroup(title: "Test Students", systemImage: "person.2.slash") {
            #if DEBUG
            TestStudentsSettingsView()
                .frame(maxWidth: .infinity)
            #else
            Text("Advanced settings are only available in debug builds.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            #endif
        }
    }

    // MARK: - Apple Intelligence Status

    @ViewBuilder
    private var appleIntelligenceStatus: some View {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            AppleIntelligenceStatusRow()
        } else {
            appleIntelligenceUnavailableView
        }
        #else
        appleIntelligenceUnavailableView
        #endif
    }

    private var appleIntelligenceUnavailableView: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(AppColors.warning)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text("Not Available")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(AppColors.warning)
                Text("Requires macOS 26 or iOS 26 with Apple Intelligence enabled")
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // iCloud Backup Toggle
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

// MARK: - Apple Intelligence Status Row

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, iOS 26.0, *)
private struct AppleIntelligenceStatusRow: View {
    private let client = LocalModelClient()

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: client.isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(client.isAvailable ? AppColors.success : AppColors.warning)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 2) {
                Text(client.isAvailable ? "Available" : "Not Available")
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(client.isAvailable ? AppColors.success : AppColors.warning)

                if !client.isAvailable {
                    Text(client.unavailabilityReason)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}
#endif

#Preview {
    SettingsView()
}
