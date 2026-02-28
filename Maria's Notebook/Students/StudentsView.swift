import OSLog
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let logger = Logger.students

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
    @Query(sort: [SortDescriptor(\LessonAssignment.id)]) private var lessonAssignmentsForChangeDetection: [LessonAssignment]
    @Query(sort: [SortDescriptor(\Lesson.id)]) private var lessonsForChangeDetection: [Lesson]
    
    // MEMORY OPTIMIZATION: Extract only IDs for change detection to avoid loading full objects
    private var attendanceRecordIDs: [UUID] {
        attendanceRecordsForChangeDetection.map { $0.id }
    }
    
    private var presentationIDs: [UUID] {
        lessonAssignmentsForChangeDetection.map { $0.id }
    }
    
    private var lessonIDs: [UUID] {
        lessonsForChangeDetection.map { $0.id }
    }
    
    // OPTIMIZATION: Cache data loaded on-demand based on mode and filters (moved to ViewModel)
    @State private var viewModel = StudentsViewModel()

    // MARK: - App Storage for Roster Mode
    @AppStorage(UserDefaultsKeys.studentsViewSortOrder) private var studentsSortOrderRaw: String = "alphabetical"
    @AppStorage(UserDefaultsKeys.studentsViewSelectedFilter) private var studentsFilterRaw: String = "all"
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // MARK: - State for Roster Mode
    @State private var showingAddStudent = false
    @State private var selectedStudentID: UUID?
    @State private var selectedStudentForSheet: Student?
    @State private var isShowingSaveError: Bool = false
    @State private var saveErrorMessage: String = ""
    
    // MARK: - State for CSV Import
    @State private var showingStudentCSVImporter: Bool = false
    @State private var importAlert: StudentsCSVImportHandler.ImportAlert? = nil
    @State private var mappingHeaders: [String] = []
    @State private var pendingMapping: StudentCSVImporter.Mapping? = nil
    @State private var pendingFileURL: URL?
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
    
    #if DEBUG
    // Temporary helper to check for duplicate IDs (debug only)
    private func checkForDuplicateIDs(in students: [Student]) {
        let uniqueIDs = Set(students.map { $0.id })
        if uniqueIDs.count != students.count {
            logger.warning("Found \(students.count - uniqueIDs.count, privacy: .public) duplicate student ID(s)")
        }
    }
    #endif

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
            .modifier(SaveErrorAlert(isPresented: $isShowingSaveError, message: saveErrorMessage))
            .alert(item: $importAlert) { alert in
                Alert(title: Text(alert.title), message: Text(alert.message), dismissButton: .default(Text("OK")))
            }
            .modifier(CSVImportSheets(
                showingImporter: $showingStudentCSVImporter,
                showingMappingSheet: $showingMappingSheet,
                mappingHeaders: mappingHeaders,
                pendingParsedImport: $pendingParsedImport,
                pendingFileURL: $pendingFileURL,
                onFileImport: handleFileImport,
                onMappingCancel: {
                    showingMappingSheet = false
                    pendingFileURL = nil
                },
                onMappingConfirm: handleMappingConfirm,
                onImportCancel: {
                    pendingParsedImport = nil
                    pendingFileURL = nil
                },
                onImportConfirm: handleImportCommit
            ))
            .sheet(item: $selectedStudentForSheet, onDismiss: {}) { student in
                StudentDetailView(student: student)
                    .id(student.id)
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
                reloadDataAsync()
            }
            .onChange(of: studentsFilterRaw) { _, _ in
                reloadDataAsync()
            }
            .onChange(of: attendanceRecordIDs) { _, _ in
                reloadDataAsync()
            }
            .onChange(of: presentationIDs) { _, _ in
                reloadDataAsync()
            }
            .onChange(of: lessonIDs) { _, _ in
                reloadDataAsync()
            }
            .onChange(of: uniqueStudentIDs) { _, _ in
                ensureInitialManualOrderIfNeeded()
                if viewModel.repairManualOrderUniquenessIfNeeded(uniqueStudents) {
                    do {
                        try modelContext.save()
                    } catch {
                        logger.warning("Failed to save after repairing manual order uniqueness: \(error)")
                    }
                }
            }
    }

    
    // MARK: - Three-Pane Layout Content
    
    private var threePaneSidebar: some View {
        VStack(spacing: 0) {
            // Sort and Filter controls at the top
            if mode == .roster {
                SortFilterControls(
                    sortOrderRaw: $studentsSortOrderRaw,
                    filterRaw: $studentsFilterRaw,
                    effectiveSortOrder: effectiveSortOrder,
                    selectedFilter: selectedFilter,
                    showEditButton: effectiveSortOrder == .manual
                )
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
                SelectStudentEmptyState()
            }
        }
    }
    
    
    // MARK: - Mode Picker Content (for ViewHeader)

    private var modePickerContent: some View {
        StudentModePicker(mode: $mode)
    }

    // MARK: - Add Student Button (for ViewHeader)

    private var addStudentButton: some View {
        AddStudentButton(
            onAddStudent: { showingAddStudent = true },
            onImportCSV: { showingStudentCSVImporter = true }
        )
    }

    // MARK: - iOS-Only Toolbar Content

    #if os(iOS)
    @ToolbarContentBuilder
    private var iOSToolbarContent: some ToolbarContent {
        let helper = StudentsViewToolbarHelper(
            mode: mode,
            effectiveSortOrder: effectiveSortOrder,
            sortOrderRaw: $studentsSortOrderRaw,
            filterRaw: $studentsFilterRaw,
            modePickerContent: { modePickerContent },
            addStudentButton: { addStudentButton },
            horizontalSizeClass: horizontalSizeClass
        )

        if helper.isCompact {
            helper.compactToolbarContent()
        } else {
            helper.regularToolbarContent()
        }
    }
    #endif

    // MARK: - Full-Screen Mode Toolbar

    @ToolbarContentBuilder
    private var fullScreenModeToolbar: some ToolbarContent {
        #if os(iOS)
        if horizontalSizeClass != .compact {
            ToolbarItem(placement: .automatic) {
                modePickerContent
                    .controlSize(.regular)
            }
        }
        #else
        ToolbarItem(placement: .automatic) {
            modePickerContent
        }
        #endif
    }

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(iOS)
        let helper = StudentsViewToolbarHelper(
            mode: mode,
            effectiveSortOrder: effectiveSortOrder,
            sortOrderRaw: $studentsSortOrderRaw,
            filterRaw: $studentsFilterRaw,
            modePickerContent: { modePickerContent },
            addStudentButton: { addStudentButton },
            horizontalSizeClass: horizontalSizeClass
        )

        if helper.isCompact {
            helper.compactToolbarContent()
        } else {
            helper.regularToolbarContent()
        }
        #else
        ToolbarItem(placement: .automatic) {
            modePickerContent
        }

        if mode == .roster || mode == .age || mode == .birthday || mode == .lastLesson {
            ToolbarItem(placement: .primaryAction) {
                addStudentButton
            }
        }
        #endif
    }



    // MARK: - Roster Grid Content

    private var rosterGridContent: some View {
        #if os(iOS)
        let renderer = StudentsContentRenderer(
            students: filteredStudents,
            effectiveSortOrder: effectiveSortOrder,
            daysSinceLastLesson: daysSinceLastLessonByStudent,
            isParsing: $isParsing,
            parsingTask: $parsingTask,
            onAddStudent: { showingAddStudent = true },
            onTapStudent: { student in
                selectedStudentForSheet = student
            },
            selectedStudentID: nil,
            horizontalSizeClass: horizontalSizeClass
        )
        #else
        let renderer = StudentsContentRenderer(
            students: filteredStudents,
            effectiveSortOrder: effectiveSortOrder,
            daysSinceLastLesson: daysSinceLastLessonByStudent,
            isParsing: $isParsing,
            parsingTask: $parsingTask,
            onAddStudent: { showingAddStudent = true },
            onTapStudent: { student in
                selectedStudentForSheet = student
            },
            selectedStudentID: nil
        )
        #endif

        return renderer.gridView
            #if DEBUG
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
            #endif
    }
    
    // MARK: - Roster Content (List View)

    private var rosterListContent: some View {
        #if os(iOS)
        let renderer = StudentsContentRenderer(
            students: filteredStudents,
            effectiveSortOrder: effectiveSortOrder,
            daysSinceLastLesson: daysSinceLastLessonByStudent,
            isParsing: $isParsing,
            parsingTask: $parsingTask,
            onAddStudent: { showingAddStudent = true },
            onTapStudent: { student in
                selectedStudentForSheet = student
            },
            selectedStudentID: $selectedStudentID,
            horizontalSizeClass: horizontalSizeClass
        )
        #else
        let renderer = StudentsContentRenderer(
            students: filteredStudents,
            effectiveSortOrder: effectiveSortOrder,
            daysSinceLastLesson: daysSinceLastLessonByStudent,
            isParsing: $isParsing,
            parsingTask: $parsingTask,
            onAddStudent: { showingAddStudent = true },
            onTapStudent: { student in
                selectedStudentForSheet = student
            },
            selectedStudentID: $selectedStudentID
        )
        #endif

        return renderer.listView { source, destination in
            handleManualReorder(from: source, to: destination)
        }
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
            presentationIDs: Set(presentationIDs),
            lessonIDs: Set(lessonIDs),
            students: uniqueStudents
        )
    }

    /// Helper to reload data asynchronously (reduces duplication in onChange handlers)
    private func reloadDataAsync() {
        Task { @MainActor in
            await loadDataOnDemand()
        }
    }

    private func ensureInitialManualOrderIfNeeded() {
        if viewModel.ensureInitialManualOrderIfNeeded(uniqueStudents) {
            do {
                try modelContext.save()
            } catch {
                logger.warning("Failed to save initial manual order: \(error)")
            }
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
        do {
            try modelContext.save()
        } catch {
            logger.warning("Failed to save manual reorder: \(error)")
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
        let specialModes: [StudentMode] = [.age, .birthday, .lastLesson]
        let specialSortOrders = ["age", "birthday", "lastLesson"]

        // Automatically set sort order when switching to age/birthday/lastLesson modes
        switch newMode {
        case .age:
            studentsSortOrderRaw = "age"
        case .birthday:
            studentsSortOrderRaw = "birthday"
        case .lastLesson:
            studentsSortOrderRaw = "lastLesson"
        case .roster where specialModes.contains(oldMode) && specialSortOrders.contains(studentsSortOrderRaw):
            // When switching back to roster from special modes, default to alphabetical
            studentsSortOrderRaw = "alphabetical"
        default:
            break
        }

        reloadDataAsync()
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
