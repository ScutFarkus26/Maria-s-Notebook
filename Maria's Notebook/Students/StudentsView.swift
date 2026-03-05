import OSLog
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let logger = Logger.students

/// Top-level view for managing and browsing students with a unified sidebar.
struct StudentsView<WorkloadContent: View>: View {
    @Binding var mode: StudentMode
    @ViewBuilder let workloadContent: WorkloadContent

    @Environment(\.modelContext) var modelContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) var calendar
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    // OPTIMIZATION: Students always needed in roster mode, so keep @Query
    @Query var students: [Student]

    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
    var uniqueStudents: [Student] { students.uniqueByID }
    var uniqueStudentIDs: [UUID] { uniqueStudents.map { $0.id } }

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
    @State var viewModel = StudentsViewModel()

    // MARK: - App Storage for Roster Mode
    @AppStorage(UserDefaultsKeys.studentsViewSortOrder) var studentsSortOrderRaw: String = "alphabetical"
    @AppStorage(UserDefaultsKeys.studentsViewSelectedFilter) var studentsFilterRaw: String = "all"
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // MARK: - State for Roster Mode
    @State var showingAddStudent = false
    @State var selectedStudentID: UUID?
    @State var selectedStudentForSheet: Student?
    @State private var isShowingSaveError: Bool = false
    @State private var saveErrorMessage: String = ""

    // MARK: - State for CSV Import
    @State var showingStudentCSVImporter: Bool = false
    @State var importAlert: StudentsCSVImportHandler.ImportAlert?
    @State var mappingHeaders: [String] = []
    @State var pendingMapping: StudentCSVImporter.Mapping?
    @State var pendingFileURL: URL?
    @State var pendingParsedImport: StudentCSVImporter.Parsed?
    @State var showingMappingSheet: Bool = false
    @State var isParsing: Bool = false
    @State var parsingTask: Task<Void, Never>?

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
            .sheet(item: $selectedStudentForSheet, onDismiss: {}, content: { student in
                StudentDetailView(student: student)
                    .id(student.id)
                #if os(macOS)
                    .frame(minWidth: 860, minHeight: 640)
                    .presentationSizingFitted()
                #else
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                #endif
            })
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

    func handleManualReorder(from source: IndexSet, to destination: Int) {
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
}
