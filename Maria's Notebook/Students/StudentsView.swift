import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Top-level view for managing and browsing students with a unified sidebar.
struct StudentsView<WorkloadContent: View>: View {
    @Binding var mode: StudentMode
    @ViewBuilder let workloadContent: WorkloadContent
    
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) private var calendar
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    
    // OPTIMIZATION: Students always needed in roster mode, so keep @Query
    @Query private var students: [Student]
    
    // OPTIMIZATION: Use lightweight queries for change detection only (IDs only)
    // Extract IDs immediately to avoid retaining full objects - significantly reduces memory usage
    @Query(sort: [SortDescriptor(\AttendanceRecord.id)]) private var attendanceRecordsForChangeDetection: [AttendanceRecord]
    @Query(sort: [SortDescriptor(\StudentLesson.id)]) private var studentLessonsForChangeDetection: [StudentLesson]
    @Query(sort: [SortDescriptor(\Lesson.id)]) private var lessonsForChangeDetection: [Lesson]
    
    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var attendanceRecordIDs: [UUID] {
        attendanceRecordsForChangeDetection.map { $0.id }
    }
    
    private var studentLessonIDs: [UUID] {
        studentLessonsForChangeDetection.map { $0.id }
    }
    
    private var lessonIDs: [UUID] {
        lessonsForChangeDetection.map { $0.id }
    }
    
    // OPTIMIZATION: Cache data loaded on-demand based on mode and filters
    @State private var cachedAttendanceRecords: [AttendanceRecord] = []
    @State private var cachedStudentLessons: [StudentLesson] = []
    @State private var cachedLessons: [UUID: Lesson] = [:]
    
    private let viewModel = StudentsViewModel()

    // MARK: - App Storage for Roster Mode
    @AppStorage("StudentsView.sortOrder") private var studentsSortOrderRaw: String = "alphabetical"
    @AppStorage("StudentsView.selectedFilter") private var studentsFilterRaw: String = "all"
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // MARK: - State for Roster Mode
    @State private var showingAddStudent = false
    @State private var selectedStudentID: UUID? = nil
    @State private var selectedStudentForSheet: Student? = nil
    @State private var isShowingSaveError: Bool = false
    @State private var saveErrorMessage: String = ""
    
    // MARK: - State for CSV Import
    @State private var showingStudentCSVImporter: Bool = false
    @State private var importAlert: ImportAlert? = nil
    @State private var mappingHeaders: [String] = []
    @State private var pendingMapping: StudentCSVImporter.Mapping? = nil
    @State private var pendingFileURL: URL? = nil
    @State private var pendingParsedImport: StudentCSVImporter.Parsed? = nil
    @State private var showingMappingSheet: Bool = false
    @State private var isParsing: Bool = false
    @State private var parsingTask: Task<Void, Never>? = nil

    private struct ImportAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    // MARK: - Computed Properties (Roster)
    private var sortOrder: SortOrder {
        switch studentsSortOrderRaw {
        case "manual": return .manual
        case "age": return .age
        case "birthday": return .birthday
        default: return .alphabetical
        }
    }

    private var selectedFilter: StudentsFilter {
        switch studentsFilterRaw {
        case "upper": return .upper
        case "lower": return .lower
        case "presentNow": return .presentNow
        case "presentToday": return .presentNow
        default: return .all
        }
    }
    
    private var levelFilters: [StudentsFilter] { [.upper, .lower] }

    // Logic helpers
    private var hiddenTestStudentIDs: Set<UUID> {
        guard showTestStudents == false else { return [] }
        let lower = testStudentNamesRaw.lowercased()
        let parts = lower.split(whereSeparator: { ch in ch == "," || ch == ";" || ch.isNewline })
        let tokens = parts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let hiddenNames = Set(tokens)
        let ids = students.compactMap { s -> UUID? in
            let name = s.fullName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return hiddenNames.contains(name) ? s.id : nil
        }
        return Set(ids)
    }

    private var presentNowIDs: Set<UUID> {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let todays = cachedAttendanceRecords.filter { rec in
            cal.isDate(rec.date, inSameDayAs: today) && (rec.status == .present || rec.status == .tardy)
        }
        // CloudKit compatibility: Convert String studentIDs to UUIDs
        var ids = Set(todays.compactMap { UUID(uuidString: $0.studentID) })
        ids.subtract(hiddenTestStudentIDs)
        return ids
    }
    
    private var presentNowCount: Int { presentNowIDs.count }

    private var daysSinceLastLessonByStudent: [UUID: Int] {
        var result: [UUID: Int] = [:]
        // ... (Existing logic for calculation)
        let excludedLessonIDs: Set<UUID> = {
            func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            let ids = cachedLessons.values.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map { $0.id }
            return Set(ids)
        }()

        let given = cachedStudentLessons.filter { $0.isGiven && !excludedLessonIDs.contains($0.resolvedLessonID) }
        var lastDateByStudent: [UUID: Date] = [:]
        for sl in given {
            let when = sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
            for sid in sl.resolvedStudentIDs {
                if let existing = lastDateByStudent[sid] {
                    if when > existing { lastDateByStudent[sid] = when }
                } else {
                    lastDateByStudent[sid] = when
                }
            }
        }
        for s in students {
            if let last = lastDateByStudent[s.id] {
                let days = LessonAgeHelper.schoolDaysSinceCreation(createdAt: last, asOf: Date(), using: modelContext, calendar: calendar)
                result[s.id] = days
            } else {
                result[s.id] = -1
            }
        }
        return result
    }

    // Computed property to get effective sort order based on mode
    private var effectiveSortOrder: SortOrder {
        switch mode {
        case .age:
            return .age
        case .birthday:
            return .birthday
        case .lastLesson:
            // Last lesson mode removed - fallback to alphabetical
            return .alphabetical
        case .roster:
            return sortOrder
        case .workOverview, .observationHeatmap:
            return .alphabetical // Not used in these modes
        }
    }
    
    private var filteredStudents: [Student] {
        let currentSortOrder = effectiveSortOrder
        return viewModel.filteredStudents(
            modelContext: modelContext,
            filter: selectedFilter,
            sortOrder: currentSortOrder,
            searchString: "", // Search not yet implemented in UI
            presentNowIDs: presentNowIDs,
            showTestStudents: showTestStudents,
            testStudentNames: testStudentNamesRaw
        )
    }

    // MARK: - Body
    
    private var mainContent: some View {
        return Group {
            if mode == .observationHeatmap {
                // Full-screen dashboard view - no split needed
                NavigationStack {
                    ObservationHeatmapView()
                        .navigationTitle("Observations")
                        .toolbar {
                            fullScreenModeToolbar
                        }
#if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
#endif
                }
            } else if mode == .workOverview {
                // Full-screen dashboard view - no split needed
                NavigationStack {
                    workloadContent
                        .navigationTitle("Workload")
                        .toolbar {
                            fullScreenModeToolbar
                        }
#if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
#endif
                }
            } else if shouldUseGridView {
                // Full-screen grid view for age/birthday modes or lastLesson sort order
                NavigationStack {
                    Group {
                        #if os(iOS)
                        if horizontalSizeClass == .compact {
                            // iPhone: Show placeholder views
                            placeholderContentForMode
                        } else {
                            // iPad: Show grid view
                            rosterGridContent
                        }
                        #else
                        // macOS: Show grid view
                        rosterGridContent
                        #endif
                    }
                    .navigationTitle("Students")
                    .toolbar {
                        toolbarContent
                    }
#if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
                }
            } else if mode == .roster {
                // Three-pane layout for Roster mode
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    // iPhone: Use single pane with sheet for details
                    NavigationStack {
                        rosterListContent
                            .navigationTitle("Students")
                            .navigationBarTitleDisplayMode(.inline)
                            .listStyle(.plain)
                            .toolbar {
                                toolbarContent
                            }
                    }
                } else {
                    // iPad: Use two-pane layout (student list + detail)
                    NavigationStack {
                        HStack(spacing: 0) {
                            threePaneSidebar
                                .frame(width: 360)
                            Divider()
                            threePaneContent
                                .frame(maxWidth: .infinity)
                        }
                        .navigationTitle("Students")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            toolbarContent
                        }
                    }
                }
                #else
                // macOS: Use two-pane layout (student list + detail)
                NavigationStack {
                    HStack(spacing: 0) {
                        threePaneSidebar
                            .frame(width: 360)
                        Divider()
                        threePaneContent
                            .frame(maxWidth: .infinity)
                    }
                    .navigationTitle("Students")
                    .toolbar {
                        toolbarContent
                    }
                }
                #endif
            } else {
                // Fallback: List-detail split (kept for safety)
                NavigationSplitView {
                    sidebarContent
                } detail: {
                    NavigationStack {
                        detailContent
                            .navigationTitle("Students")
                            .toolbar {
                                toolbarContent
                            }
#if os(iOS)
                            .navigationBarTitleDisplayMode(.inline)
#endif
                    }
                }
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
            }
        }
    }
    
    // MARK: - Grid View Support
    
    private var shouldUseGridView: Bool {
        mode == .age || mode == .birthday || mode == .lastLesson
    }
    
    // MARK: - iPhone Placeholder Views
    
    #if os(iOS)
    private var placeholderContentForMode: some View {
        Group {
            switch mode {
            case .birthday:
                BirthdayModePlaceholderView()
            case .age:
                AgeModePlaceholderView()
            case .lastLesson:
                LastLessonModePlaceholderView()
            default:
                rosterGridContent
            }
        }
    }
    #endif

    // Helper to break up complex view builder expression
    private var contentWithSheetsAndAlerts: some View {
        mainContent
            .sheet(isPresented: $showingAddStudent) {
                AddStudentView()
                    .presentationSizingFitted()
            }
            .alert("Save Failed", isPresented: $isShowingSaveError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(saveErrorMessage)
            }
            .alert(item: $importAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
            .fileImporter(
                isPresented: $showingStudentCSVImporter,
                allowedContentTypes: [.commaSeparatedText, .plainText]
            ) { result in
                handleFileImport(result)
            }
            .sheet(isPresented: $showingMappingSheet) {
                StudentCSVMappingView(headers: mappingHeaders, onCancel: {
                    showingMappingSheet = false
                    pendingFileURL = nil
                }, onConfirm: { mapping in
                    handleMappingConfirm(mapping)
                })
            }
            .sheet(item: $pendingParsedImport, onDismiss: {}) { (parsed: StudentCSVImporter.Parsed) in
                StudentImportPreviewView(parsed: parsed, onCancel: {
                    pendingParsedImport = nil
                    pendingFileURL = nil
                }, onConfirm: { filtered in
                    handleImportCommit(filtered)
                })
                .frame(minWidth: 620, minHeight: 520)
            }
            .sheet(item: $selectedStudentForSheet, onDismiss: {}) { (student: Student) in
                StudentDetailView(student: student)
                    .id(student.id) // <--- Add this safety check
                #if os(macOS)
                    .frame(minWidth: 860, minHeight: 640)
                    .presentationSizingFitted()
                #else
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                #endif
            }
    }
    
    var body: some View {
        contentWithSheetsAndAlerts
            .onChange(of: appRouter.navigationDestination) { _, destination in
                handleNavigationDestinationChange(destination)
            }
#if os(iOS)
            .onAppear {
                if horizontalSizeClass == .compact { mode = .roster }
            }
#endif
            .task {
                ensureInitialManualOrderIfNeeded()
                await loadDataOnDemand()
            }
            .onChange(of: mode) { oldMode, newMode in
                handleModeChange(oldMode: oldMode, newMode: newMode)
            }
            .onChange(of: studentsSortOrderRaw) { _, _ in
                Task { @MainActor in
                    await loadDataOnDemand()
                }
            }
            .onChange(of: studentsFilterRaw) { _, _ in
                Task { @MainActor in
                    await loadDataOnDemand()
                }
            }
            .onChange(of: attendanceRecordIDs) { _, _ in
                Task { @MainActor in
                    await loadDataOnDemand()
                }
            }
            .onChange(of: studentLessonIDs) { _, _ in
                Task { @MainActor in
                    await loadDataOnDemand()
                }
            }
            .onChange(of: lessonIDs) { _, _ in
                Task { @MainActor in
                    await loadDataOnDemand()
                }
            }
            .onChange(of: students.map { $0.id }) { _, _ in
                ensureInitialManualOrderIfNeeded()
                if viewModel.repairManualOrderUniquenessIfNeeded(students) {
                    try? modelContext.save()
                }
            }
    }

    // MARK: - Sidebar Content
    
    private var sidebarContent: some View {
        NavigationStack {
            rosterListContent
                .navigationTitle("Students")
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
#endif
        }
        .listStyle(.sidebar)
    }
    
    // MARK: - Three-Pane Layout Content
    
    private var threePaneSidebar: some View {
        VStack(spacing: 0) {
            // Sort and Filter controls at the top
            if mode == .roster {
                rosterSortFilterControls
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.bar)
                Divider()
            }
            
            // Student list
            NavigationStack {
                rosterListContent
                    .navigationTitle("Students")
#if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
            }
            .listStyle(.sidebar)
        }
    }
    
    private var threePaneContent: some View {
        NavigationStack {
            if let id = selectedStudentID, let student = students.first(where: { $0.id == id }) {
                StudentDetailView(student: student)
                    .id(student.id)
                    .navigationTitle(student.fullName)
#if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
            } else {
                ContentUnavailableView {
                    Label("Select a Student", systemImage: "person.circle")
                } description: {
                    Text("Choose a student from the list to view their details.")
                }
            }
        }
    }
    
    private var rosterSortFilterControls: some View {
        HStack(spacing: 12) {
            // Sort Order Picker
            Menu {
                Button {
                    withAnimation { studentsSortOrderRaw = "alphabetical" }
                } label: {
                    Label("A–Z", systemImage: "textformat.abc")
                    if effectiveSortOrder == .alphabetical {
                        Image(systemName: "checkmark")
                    }
                }
                Button {
                    withAnimation { studentsSortOrderRaw = "manual" }
                } label: {
                    Label("Manual", systemImage: "arrow.up.arrow.down")
                    if effectiveSortOrder == .manual {
                        Image(systemName: "checkmark")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.arrow.down")
                    Text("Sort")
                }
                .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            // Filter Picker
            Menu {
                Button {
                    withAnimation { studentsFilterRaw = "all" }
                } label: {
                    Label("All", systemImage: "person.3.fill")
                    if selectedFilter == .all {
                        Image(systemName: "checkmark")
                    }
                }
                Button {
                    withAnimation { studentsFilterRaw = "presentNow" }
                } label: {
                    Label("Present Now", systemImage: "checkmark.circle.fill")
                    if selectedFilter == .presentNow {
                        Image(systemName: "checkmark")
                    }
                }
                Button {
                    withAnimation { studentsFilterRaw = "upper" }
                } label: {
                    Label("Upper", systemImage: "circle.fill")
                    if selectedFilter == .upper {
                        Image(systemName: "checkmark")
                    }
                }
                Button {
                    withAnimation { studentsFilterRaw = "lower" }
                } label: {
                    Label("Lower", systemImage: "circle.fill")
                    if selectedFilter == .lower {
                        Image(systemName: "checkmark")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Filter")
                }
                .font(.system(size: 13, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Spacer()
            
            // Edit button (only show in manual sort mode, iOS only)
            #if os(iOS)
            if effectiveSortOrder == .manual {
                EditButton()
                    .controlSize(.small)
            }
            #endif
        }
    }
    
    // MARK: - Full-Screen Mode Toolbar
    
    @ToolbarContentBuilder
    private var fullScreenModeToolbar: some ToolbarContent {
        #if os(iOS)
        if horizontalSizeClass != .compact {
            // iPad layout: Use segmented picker
            ToolbarItem(placement: .automatic) {
                Picker("Mode", selection: $mode) {
                    Label("Roster", systemImage: "person.3").tag(StudentMode.roster)
                    Label("Age", systemImage: "calendar").tag(StudentMode.age)
                    Label("Birthday", systemImage: "gift").tag(StudentMode.birthday)
                    Label("Last Lesson", systemImage: "clock.badge.exclamationmark").tag(StudentMode.lastLesson)
                    Label("Workload", systemImage: "doc.text").tag(StudentMode.workOverview)
                    Label("Observations", systemImage: "chart.bar.fill").tag(StudentMode.observationHeatmap)
                }
                .pickerStyle(.segmented)
                .controlSize(.regular)
            }
        }
        #else
        // macOS layout: Use segmented picker
        ToolbarItem(placement: .automatic) {
            Picker("Mode", selection: $mode) {
                Label("Roster", systemImage: "person.3").tag(StudentMode.roster)
                Label("Age", systemImage: "calendar").tag(StudentMode.age)
                Label("Birthday", systemImage: "gift").tag(StudentMode.birthday)
                Label("Last Lesson", systemImage: "clock.badge.exclamationmark").tag(StudentMode.lastLesson)
                Label("Workload", systemImage: "doc.text").tag(StudentMode.workOverview)
                Label("Observations", systemImage: "chart.bar.fill").tag(StudentMode.observationHeatmap)
            }
            .pickerStyle(.segmented)
        }
        #endif
    }
    
    // MARK: - Toolbar Content
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            // iPhone layout: Use menus instead of segmented picker
            // REMOVED mode switch menu per instructions
            
            // Sort and Filter controls moved to top of second pane in roster mode
            // (iPhone compact layout still uses single pane, so controls remain in toolbar for now)
            if mode == .roster && horizontalSizeClass == .compact {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Section("Sort") {
                            Button {
                                withAnimation { studentsSortOrderRaw = "alphabetical" }
                            } label: {
                                Label("A–Z", systemImage: "textformat.abc")
                                if effectiveSortOrder == .alphabetical {
                                    Image(systemName: "checkmark")
                                }
                            }
                            Button {
                                withAnimation { studentsSortOrderRaw = "manual" }
                            } label: {
                                Label("Manual", systemImage: "arrow.up.arrow.down")
                                if effectiveSortOrder == .manual {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        
                        Section("Filter") {
                            Button {
                                withAnimation { studentsFilterRaw = "all" }
                            } label: {
                                Label("All", systemImage: "person.3.fill")
                                if selectedFilter == .all {
                                    Image(systemName: "checkmark")
                                }
                            }
                            Button {
                                withAnimation { studentsFilterRaw = "presentNow" }
                            } label: {
                                Label("Present Now", systemImage: "checkmark.circle.fill")
                                if selectedFilter == .presentNow {
                                    Image(systemName: "checkmark")
                                }
                            }
                            Button {
                                withAnimation { studentsFilterRaw = "upper" }
                            } label: {
                                Label("Upper", systemImage: "circle.fill")
                                if selectedFilter == .upper {
                                    Image(systemName: "checkmark")
                                }
                            }
                            Button {
                                withAnimation { studentsFilterRaw = "lower" }
                            } label: {
                                Label("Lower", systemImage: "circle.fill")
                                if selectedFilter == .lower {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    } label: {
                        Label("Options", systemImage: "ellipsis.circle")
                    }
                }
                
                if effectiveSortOrder == .manual {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }
        } else {
            // iPad layout: Use segmented picker
            ToolbarItem(placement: .automatic) {
                Picker("Mode", selection: $mode) {
                    Label("Roster", systemImage: "person.3").tag(StudentMode.roster)
                    Label("Age", systemImage: "calendar").tag(StudentMode.age)
                    Label("Birthday", systemImage: "gift").tag(StudentMode.birthday)
                    Label("Last Lesson", systemImage: "clock.badge.exclamationmark").tag(StudentMode.lastLesson)
                    Label("Workload", systemImage: "doc.text").tag(StudentMode.workOverview)
                    Label("Observations", systemImage: "chart.bar.fill").tag(StudentMode.observationHeatmap)
                }
                .pickerStyle(.segmented)
                .controlSize(.regular)
            }
            
            // Sort and Filter controls moved to top of second pane in roster mode
            // Edit button also moved there
        }
        #else
        // macOS layout: Use segmented picker
        ToolbarItem(placement: .automatic) {
            Picker("Mode", selection: $mode) {
                Label("Roster", systemImage: "person.3").tag(StudentMode.roster)
                Label("Age", systemImage: "calendar").tag(StudentMode.age)
                Label("Birthday", systemImage: "gift").tag(StudentMode.birthday)
                Label("Last Lesson", systemImage: "clock.badge.exclamationmark").tag(StudentMode.lastLesson)
                Label("Workload", systemImage: "doc.text").tag(StudentMode.workOverview)
                Label("Observations", systemImage: "chart.bar.fill").tag(StudentMode.observationHeatmap)
            }
            .pickerStyle(.segmented)
        }
        
        // Sort and Filter controls moved to top of second pane in roster mode
        #endif
        
        // Add Student button (show in roster/age/birthday/lastLesson modes)
        if mode == .roster || mode == .age || mode == .birthday || mode == .lastLesson {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddStudent = true
                } label: {
                    Label("Add Student", systemImage: "plus.circle.fill")
                }
                .keyboardShortcut("n", modifiers: [.command])
                .contextMenu {
                    Button {
                        showingStudentCSVImporter = true
                    } label: {
                        Label("Import Students from CSV…", systemImage: "arrow.down.doc")
                    }
                }
            }
        }
    }

    // MARK: - Sidebar (unused - kept for reference)

    private var unifiedSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // SECTION 1: NAVIGATION
                VStack(alignment: .leading, spacing: 4) {
                    Text("MODE")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                    
                    SidebarNavButton(title: "Roster", icon: "person.3", isSelected: mode == .roster) {
                        mode = .roster
                    }
                    SidebarNavButton(title: "Workload", icon: "doc.text", isSelected: mode == .workOverview) {
                        mode = .workOverview
                    }
                }

                // SECTION 2: ROSTER TOOLS (Only visible in Roster Mode)
                if mode == .roster {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Text("SORT ORDER")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)

                        SidebarFilterButton(icon: "textformat.abc", title: "A–Z", color: .accentColor, isSelected: sortOrder == .alphabetical) {
                            withAnimation { studentsSortOrderRaw = "alphabetical" }
                        }
                        SidebarFilterButton(icon: "calendar", title: "Age", color: .accentColor, isSelected: sortOrder == .age) {
                            withAnimation { studentsSortOrderRaw = "age" }
                        }
                        SidebarFilterButton(icon: "gift", title: "Birthday", color: .accentColor, isSelected: sortOrder == .birthday) {
                            withAnimation { studentsSortOrderRaw = "birthday" }
                        }
                        SidebarFilterButton(icon: "arrow.up.arrow.down", title: "Manual", color: .accentColor, isSelected: sortOrder == .manual) {
                            withAnimation { studentsSortOrderRaw = "manual" }
                        }

                        Text("FILTERS")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 8)

                        SidebarFilterButton(icon: "person.3.fill", title: "All", color: .accentColor, isSelected: selectedFilter == .all) {
                            withAnimation { studentsFilterRaw = "all" }
                        }
                        SidebarFilterButton(
                            icon: "checkmark.circle.fill",
                            title: "Present Now",
                            color: .green,
                            isSelected: selectedFilter == .presentNow,
                            trailingBadgeText: presentNowCount > 0 ? "\(presentNowCount)" : nil,
                            trailingBadgeColor: .green
                        ) {
                            withAnimation { studentsFilterRaw = "presentNow" }
                        }
                        
                        ForEach(levelFilters, id: \.self) { filter in
                            SidebarFilterButton(icon: "circle.fill", title: filter.title, color: filter.color, isSelected: selectedFilter == filter) {
                                withAnimation { selectedFilterRawAssignment(for: filter) }
                            }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .padding(.vertical, 16)
        }
    }

    // MARK: - Roster Grid Content
    
    private var rosterGridContent: some View {
        Group {
            if filteredStudents.isEmpty {
                ContentUnavailableView {
                    Label("No students yet", systemImage: "person.3")
                } description: {
                    Text("Click the plus button to add your first student.")
                } actions: {
                    Button {
                        showingAddStudent = true
                    } label: {
                        Label("Add Student", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                StudentsCardsGridView(
                    students: filteredStudents,
                    isBirthdayMode: effectiveSortOrder == .birthday,
                    isAgeMode: effectiveSortOrder == .age,
                    isLastLessonMode: false,
                    lastLessonDays: [:],
                    isManualMode: false,
                    onTapStudent: { student in
                        selectedStudentForSheet = student
                    },
                    onReorder: { movingStudent, fromIndex, toIndex, subset in
                        // Reordering not supported in grid view modes
                    }
                )
            }
        }
        .overlay {
            ParsingOverlay(isParsing: $isParsing) {
                parsingTask?.cancel()
            }
        }
    }
    
    // MARK: - Roster Content (List View)
    
    private var rosterListContent: some View {
        Group {
            if filteredStudents.isEmpty {
                ContentUnavailableView {
                    Label("No students yet", systemImage: "person.3")
                } description: {
                    Text("Click the plus button to add your first student.")
                } actions: {
                    Button {
                        showingAddStudent = true
                    } label: {
                        Label("Add Student", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $selectedStudentID) {
                    ForEach(filteredStudents, id: \.id) { student in
                        StudentListRow(
                            student: student,
                            sortOrder: effectiveSortOrder,
                            daysSinceLastLesson: daysSinceLastLessonByStudent[student.id]
                        )
                        .tag(student.id)
                        #if os(iOS)
                        .onTapGesture {
                            // On compact devices, still use sheet; on regular, use three-pane
                            if horizontalSizeClass == .compact {
                                selectedStudentForSheet = student
                            } else {
                                selectedStudentID = student.id
                            }
                        }
                        #else
                        // macOS: selection binding handles it automatically
                        #endif
                    }
                    .onMove { source, destination in
                        handleManualReorder(from: source, to: destination)
                    }
                }
            }
        }
        .overlay {
            ParsingOverlay(isParsing: $isParsing) {
                parsingTask?.cancel()
            }
        }
    }
    
    // MARK: - Detail Content
    
    private var detailContent: some View {
        Group {
            if let id = selectedStudentID, let student = students.first(where: { $0.id == id }) {
                HStack(alignment: .top, spacing: 0) {
                    StudentDetailView(student: student)
                        .frame(maxWidth: 700)
                        .id(student.id) // <--- Force recreation when student changes
                    Spacer()
                }
            } else {
                ContentUnavailableView {
                    Label("Select a Student", systemImage: "person.circle")
                } description: {
                    Text("Choose a student from the list to view their details.")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Logic Helpers
    
    // MARK: - On-Demand Data Loading
    
    /// Loads data on-demand based on current mode and filters
    @MainActor
    private func loadDataOnDemand() async {
        guard mode == .roster || mode == .age || mode == .birthday || mode == .lastLesson else {
            // Clear caches when not in roster mode
            cachedAttendanceRecords = []
            cachedStudentLessons = []
            cachedLessons = [:]
            return
        }
        
        // Load attendanceRecords - always load in roster mode to show "Present Now" count in sidebar
        // Fetch only today's attendance records
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        do {
            let descriptor = FetchDescriptor<AttendanceRecord>(
                predicate: #Predicate { rec in
                    rec.date >= today && rec.date < tomorrow
                },
                sortBy: [SortDescriptor(\.date, order: .forward)]
            )
            cachedAttendanceRecords = try modelContext.fetch(descriptor)
        } catch {
            cachedAttendanceRecords = modelContext.safeFetch(FetchDescriptor<AttendanceRecord>())
                .filter { cal.isDate($0.date, inSameDayAs: today) }
        }
        
        // Clear studentLessons cache (no longer needed for lastLesson mode)
        cachedStudentLessons = []
        cachedLessons = [:]
    }

    private func ensureInitialManualOrderIfNeeded() {
        if viewModel.ensureInitialManualOrderIfNeeded(students) {
            try? modelContext.save()
        }
    }
    
    private func assignManualOrder(from orderedIDs: [UUID]) {
        for (idx, id) in orderedIDs.enumerated() {
            if let s = students.first(where: { $0.id == id }) {
                s.manualOrder = idx
            }
        }
    }
    
    private func handleManualReorder(from source: IndexSet, to destination: Int) {
        guard effectiveSortOrder == .manual, let fromIndex = source.first else { return }
        let movingStudent = filteredStudents[fromIndex]
        let newAllIDs = viewModel.mergeReorderedSubsetIntoAll(
            movingID: movingStudent.id,
            from: fromIndex,
            to: destination,
            current: filteredStudents,
            allStudents: students
        )
        assignManualOrder(from: newAllIDs)
        try? modelContext.save()
    }
    
    private func selectedFilterRawAssignment(for filter: StudentsFilter) {
        switch filter {
        case .upper: studentsFilterRaw = "upper"
        case .lower: studentsFilterRaw = "lower"
        case .presentNow: studentsFilterRaw = "presentNow"
        case .all: studentsFilterRaw = "all"
        }
    }

    // MARK: - Navigation and Lifecycle Helpers
    
    private func handleNavigationDestinationChange(_ destination: AppRouter.NavigationDestination?) {
        guard let destination = destination else { return }
        if case .newStudent = destination {
            mode = .roster
            showingAddStudent = true
            appRouter.clearNavigation()
        } else if case .importStudents = destination {
            mode = .roster
            showingStudentCSVImporter = true
            appRouter.clearNavigation()
        } else if case .openStudentDetail(let studentID) = destination {
            mode = .roster
            selectedStudentID = studentID
            appRouter.clearNavigation()
        }
    }
    
    private func handleModeChange(oldMode: StudentMode, newMode: StudentMode) {
        // Automatically set sort order when switching to age/birthday/lastLesson modes
        if newMode == .age {
            studentsSortOrderRaw = "age"
        } else if newMode == .birthday {
            studentsSortOrderRaw = "birthday"
        } else if newMode == .lastLesson {
            // Last lesson mode removed - use alphabetical as fallback
            studentsSortOrderRaw = "alphabetical"
        } else if (oldMode == .age || oldMode == .birthday || oldMode == .lastLesson) && newMode == .roster {
            // When switching back to roster from age/birthday/lastLesson, default to alphabetical
            if studentsSortOrderRaw == "age" || studentsSortOrderRaw == "birthday" || studentsSortOrderRaw == "lastLesson" {
                studentsSortOrderRaw = "alphabetical"
            }
        }
        Task { @MainActor in
            await loadDataOnDemand()
        }
    }

    // MARK: - CSV Handlers

    private func handleFileImport(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            parsingTask?.cancel()
            isParsing = true
            parsingTask = StudentsImportCoordinator.startHeaderScan(from: url, onParsed: { headers, mapping in
                self.pendingFileURL = url
                self.mappingHeaders = headers
                self.pendingMapping = mapping
                self.showingMappingSheet = true
            }, onError: { error in
                self.importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            }, onFinally: {
                self.isParsing = false
                self.parsingTask = nil
            })
        } catch {
            importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            isParsing = false
            parsingTask = nil
        }
    }

    private func handleMappingConfirm(_ mapping: StudentCSVImporter.Mapping) {
        guard let fileURL = pendingFileURL else { return }
        parsingTask?.cancel()
        isParsing = true
        parsingTask = StudentsImportCoordinator.startMappedParse(from: fileURL, mapping: mapping, students: self.students, onParsed: { parsed in
            self.pendingParsedImport = parsed
            self.showingMappingSheet = false
        }, onError: { error in
            self.importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
            self.showingMappingSheet = false
        }, onFinally: {
            self.isParsing = false
            self.parsingTask = nil
        })
    }

    private func handleImportCommit(_ filtered: StudentCSVImporter.Parsed) {
        do {
            let result = try ImportCommitService.commitStudents(parsed: filtered, into: modelContext, existingStudents: students)
            importAlert = ImportAlert(title: result.title, message: result.message)
        } catch {
            importAlert = ImportAlert(title: "Import Failed", message: error.localizedDescription)
        }
        pendingParsedImport = nil
    }
}

// MARK: - Sidebar Button Helper
struct SidebarNavButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
    }
}

