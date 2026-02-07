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

    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
    private var uniqueStudents: [Student] { students.uniqueByID }
    private var uniqueStudentIDs: [UUID] { uniqueStudents.map { $0.id } }

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
    
    // OPTIMIZATION: Cache data loaded on-demand based on mode and filters (moved to ViewModel)
    @StateObject private var viewModel = StudentsViewModel()

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
    @State private var importAlert: StudentsCSVImportHandler.ImportAlert? = nil
    @State private var mappingHeaders: [String] = []
    @State private var pendingMapping: StudentCSVImporter.Mapping? = nil
    @State private var pendingFileURL: URL? = nil
    @State private var pendingParsedImport: StudentCSVImporter.Parsed? = nil
    @State private var showingMappingSheet: Bool = false
    @State private var isParsing: Bool = false
    @State private var parsingTask: Task<Void, Never>? = nil

    // MARK: - Computed Properties (Roster)
    private var sortOrder: SortOrder {
        switch studentsSortOrderRaw {
        case "manual": return .manual
        case "age": return .age
        case "birthday": return .birthday
        case "lastLesson": return .lastLesson
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
        viewModel.hiddenTestStudentIDs(
            students: uniqueStudents,
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    private var presentNowIDs: Set<UUID> {
        viewModel.presentNowIDs(
            from: viewModel.cachedAttendanceRecords,
            calendar: calendar
        )
    }
    
    private var presentNowCount: Int { presentNowIDs.count }

    // OPTIMIZATION: Use cached version instead of recomputing on every view update
    private var daysSinceLastLessonByStudent: [UUID: Int] { viewModel.cachedDaysSinceLastLesson }

    // Computed property to get effective sort order based on mode
    private var effectiveSortOrder: SortOrder {
        switch mode {
        case .age:
            return .age
        case .birthday:
            return .birthday
        case .lastLesson:
            return .lastLesson
        case .roster:
            return sortOrder
        case .workOverview, .observationHeatmap:
            return .alphabetical // Not used in these modes
        }
    }
    
    private var filteredStudents: [Student] {
        let currentSortOrder = effectiveSortOrder
        let base = viewModel.filteredStudents(
            modelContext: modelContext,
            filter: selectedFilter,
            sortOrder: currentSortOrder,
            searchString: "", // Search not yet implemented in UI
            presentNowIDs: presentNowIDs,
            showTestStudents: showTestStudents,
            testStudentNames: testStudentNamesRaw
        )

        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
        let deduplicated = base.uniqueByID

        // Apply lastLesson sorting in-memory (requires access to presentation data)
        if currentSortOrder == .lastLesson {
            let daysMap = daysSinceLastLessonByStudent
            return deduplicated.sorted { lhs, rhs in
                let lDays = daysMap[lhs.id] ?? -1
                let rDays = daysMap[rhs.id] ?? -1
                // Students with no presentations (-1) go first, then sort by most days since last presentation
                if lDays == -1 && rDays == -1 {
                    return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
                }
                if lDays == -1 { return true }
                if rDays == -1 { return false }
                if lDays == rDays {
                    return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
                }
                return lDays > rDays // More days = needs lesson more urgently
            }
        }

        return deduplicated
    }
    
    // Temporary helper to check for duplicate IDs
    private func checkForDuplicateIDs(in students: [Student]) {
        var seenIDs: Set<UUID> = []
        var duplicates: [UUID] = []
        
        for student in students {
            if seenIDs.contains(student.id) {
                duplicates.append(student.id)
            } else {
                seenIDs.insert(student.id)
            }
        }

        if !duplicates.isEmpty {
            #if DEBUG
            print("found duplicate ID: \(duplicates)")
            #endif
        }
    }

    // MARK: - Body

    // MARK: - macOS Mode-Specific Content (no NavigationStack wrapper)
    #if os(macOS)
    @ViewBuilder
    private var macOSModeContent: some View {
        switch mode {
        case .observationHeatmap:
            ObservationHeatmapView()
        case .workOverview:
            workloadContent
        case .age, .birthday, .lastLesson:
            rosterGridContent
        case .roster:
            HStack(spacing: 0) {
                threePaneSidebar
                    .frame(width: 360)
                Divider()
                threePaneContent
                    .frame(maxWidth: .infinity)
            }
        }
    }
    #endif

    private var mainContent: some View {
        #if os(macOS)
        // macOS: Single NavigationStack with switching content for smooth transitions
        NavigationStack {
            VStack(spacing: 0) {
                ViewHeader(title: "Students") {
                    modePickerContent

                    Spacer()
                        .frame(width: 24)

                    addStudentButton
                }
                Divider()
                macOSModeContent
            }
        }
        #else
        // iOS: Keep existing structure for different layout needs
        Group {
            if mode == .observationHeatmap {
                // Full-screen dashboard view - no split needed
                NavigationStack {
                    ObservationHeatmapView()
                    .navigationTitle("Observations")
                    .toolbar {
                        fullScreenModeToolbar
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else if mode == .workOverview {
                // Full-screen dashboard view - no split needed
                NavigationStack {
                    workloadContent
                    .navigationTitle("Open Work")
                    .toolbar {
                        fullScreenModeToolbar
                    }
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else if shouldUseGridView {
                // Full-screen grid view for age/birthday modes or lastLesson sort order
                NavigationStack {
                    Group {
                        if horizontalSizeClass == .compact {
                            // iPhone: Show placeholder views
                            placeholderContentForMode
                        } else {
                            // iPad: Show grid view
                            rosterGridContent
                        }
                    }
                    .toolbar {
                        iOSToolbarContent
                    }
                    .navigationTitle("Students")
                    .navigationBarTitleDisplayMode(.inline)
                }
            } else if mode == .roster {
                // Three-pane layout for Roster mode
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
                            .navigationBarTitleDisplayMode(.inline)
                    }
                }
                .navigationSplitViewColumnWidth(min: 320, ideal: 360, max: 420)
            }
        }
        #endif
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
            .onChange(of: uniqueStudentIDs) { _, _ in
                ensureInitialManualOrderIfNeeded()
                if viewModel.repairManualOrderUniquenessIfNeeded(uniqueStudents) {
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
            if let id = selectedStudentID, let student = uniqueStudents.first(where: { $0.id == id }) {
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
    
    // MARK: - Mode Picker Content (for ViewHeader)

    private var modePickerContent: some View {
        Picker("Mode", selection: $mode) {
            Label("Roster", systemImage: "person.3").tag(StudentMode.roster)
            Label("Open Work", systemImage: "doc.text").tag(StudentMode.workOverview)
            Label("Ages", systemImage: "calendar").tag(StudentMode.age)
            Label("Birthday", systemImage: "gift").tag(StudentMode.birthday)
            Label("Needs Lesson", systemImage: "clock.badge.exclamationmark").tag(StudentMode.lastLesson)
            Label("Observations", systemImage: "chart.bar.fill").tag(StudentMode.observationHeatmap)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    // MARK: - Add Student Button (for ViewHeader)

    private var addStudentButton: some View {
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

    // MARK: - iOS-Only Toolbar Content

    #if os(iOS)
    @ToolbarContentBuilder
    private var iOSToolbarContent: some ToolbarContent {
        if horizontalSizeClass == .compact {
            // iPhone layout for compact size class
            if mode == .roster {
                ToolbarItem(placement: .navigationBarTrailing) {
                    StudentsSortFilterMenu(
                        sortOrderRaw: $studentsSortOrderRaw,
                        filterRaw: $studentsFilterRaw
                    )
                }

                if effectiveSortOrder == .manual {
                    ToolbarItem(placement: .navigationBarLeading) {
                        EditButton()
                    }
                }
            }

            // Add Student button for iPhone
            if mode == .roster || mode == .age || mode == .birthday || mode == .lastLesson {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddStudent = true
                    } label: {
                        Label("Add Student", systemImage: "plus.circle.fill")
                    }
                }
            }
        } else {
            // iPad layout: Use segmented picker in toolbar
            ToolbarItem(placement: .automatic) {
                modePickerContent
                    .controlSize(.regular)
            }

            // Add Student button for iPad
            if mode == .roster || mode == .age || mode == .birthday || mode == .lastLesson {
                ToolbarItem(placement: .primaryAction) {
                    addStudentButton
                }
            }
        }
    }
    #endif

    // MARK: - Full-Screen Mode Toolbar

    @ToolbarContentBuilder
    private var fullScreenModeToolbar: some ToolbarContent {
        #if os(iOS)
        if horizontalSizeClass != .compact {
            // iPad layout: Use segmented picker
            ToolbarItem(placement: .automatic) {
                modePickerContent
                    .controlSize(.regular)
            }
        }
        #else
        // macOS layout: Use segmented picker
        ToolbarItem(placement: .automatic) {
            modePickerContent
        }
        #endif
    }

    // MARK: - Toolbar Content
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            // iPhone layout: Use menus instead of segmented picker
            // Sort and Filter controls for roster mode
            if mode == .roster && horizontalSizeClass == .compact {
                ToolbarItem(placement: .navigationBarTrailing) {
                    StudentsSortFilterMenu(
                        sortOrderRaw: $studentsSortOrderRaw,
                        filterRaw: $studentsFilterRaw
                    )
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
                modePickerContent
                    .controlSize(.regular)
            }

            // Sort and Filter controls moved to top of second pane in roster mode
            // Edit button also moved there
        }
        #else
        // macOS layout: Use segmented picker
        ToolbarItem(placement: .automatic) {
            modePickerContent
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
                    isLastLessonMode: effectiveSortOrder == .lastLesson,
                    lastLessonDays: effectiveSortOrder == .lastLesson ? daysSinceLastLessonByStudent : [:],
                    isManualMode: false,
                    onTapStudent: { student in
                        selectedStudentForSheet = student
                    },
                    onReorder: { movingStudent, fromIndex, toIndex, subset in
                        // Reordering not supported in grid view modes
                    }
                )
                .onAppear {
                    checkForDuplicateIDs(in: filteredStudents)
                }
                .onChange(of: filteredStudents.count) {
                    checkForDuplicateIDs(in: filteredStudents)
                }
                .onChange(of: selectedFilter) {
                    checkForDuplicateIDs(in: filteredStudents)
                }
                .onChange(of: effectiveSortOrder) {
                    checkForDuplicateIDs(in: filteredStudents)
                }
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
            if let id = selectedStudentID, let student = uniqueStudents.first(where: { $0.id == id }) {
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
        viewModel.loadDataOnDemand(
            mode: mode,
            modelContext: modelContext,
            calendar: calendar,
            attendanceRecordIDs: Set(attendanceRecordIDs),
            studentLessonIDs: Set(studentLessonIDs),
            lessonIDs: Set(lessonIDs),
            students: uniqueStudents
        )
    }

    private func ensureInitialManualOrderIfNeeded() {
        if viewModel.ensureInitialManualOrderIfNeeded(uniqueStudents) {
            try? modelContext.save()
        }
    }

    private func assignManualOrder(from orderedIDs: [UUID]) {
        for (idx, id) in orderedIDs.enumerated() {
            if let s = uniqueStudents.first(where: { $0.id == id }) {
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
            allStudents: uniqueStudents
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
            studentsSortOrderRaw = "lastLesson"
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
        isParsing = true
        let importResult = StudentsCSVImportHandler.handleFileImport(
            result,
            cancellingTask: parsingTask,
            onHeadersScanned: { headers, mapping, fileURL in
                self.pendingFileURL = fileURL
                self.mappingHeaders = headers
                self.pendingMapping = mapping
                self.showingMappingSheet = true
            },
            onError: { alert in
                self.importAlert = alert
            },
            onFinally: {
                self.isParsing = false
                self.parsingTask = nil
            }
        )
        parsingTask = importResult.task
        if let error = importResult.immediateError {
            importAlert = error
        }
    }

    private func handleMappingConfirm(_ mapping: StudentCSVImporter.Mapping) {
        isParsing = true
        parsingTask = StudentsCSVImportHandler.handleMappingConfirm(
            mapping: mapping,
            fileURL: pendingFileURL,
            students: students,
            cancellingTask: parsingTask,
            onParsed: { parsed in
                self.pendingParsedImport = parsed
                self.showingMappingSheet = false
            },
            onError: { alert in
                self.importAlert = alert
                self.showingMappingSheet = false
            },
            onFinally: {
                self.isParsing = false
                self.parsingTask = nil
            }
        )
    }

    private func handleImportCommit(_ filtered: StudentCSVImporter.Parsed) {
        importAlert = StudentsCSVImportHandler.handleImportCommit(
            filtered,
            modelContext: modelContext,
            existingStudents: students
        )
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

