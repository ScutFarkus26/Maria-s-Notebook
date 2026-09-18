import Combine
import CoreData
import OSLog
import SwiftUI
import UniformTypeIdentifiers

nonisolated private let logger = Logger.students

// Top-level view for managing and browsing students.
//
// One NavigationSplitView spine on every platform:
// - Sidebar: roster list with search, scope chips, sort-contextual rows,
//   and a collapsible Withdrawn section.
// - Detail: the selected student inline on iPhone, or the mobile grid browser
//   when no student is selected.
struct StudentsView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) var calendar
    @Environment(\.dependencies) var dependencies
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    // OPTIMIZATION: Students always needed, so keep @FetchRequest
    @FetchRequest(sortDescriptors: []) var students: FetchedResults<CDStudent>

    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
    var uniqueStudents: [CDStudent] { Array(students).uniqueByID }
    var uniqueStudentIDs: [UUID] { uniqueStudents.compactMap(\.id) }

    // PERF: Use lightweight count-based change detection instead of loading full tables.
    // SwiftData @Query always materializes full objects, so we use fetchCount() instead.
    @State private var attendanceChangeToken: Int = 0
    @State private var presentationChangeToken: Int = 0
    @State private var lessonChangeToken: Int = 0

    // OPTIMIZATION: Cache data loaded on-demand based on filters (moved to ViewModel)
    @State var viewModel = StudentsViewModel()

    // MARK: - Persisted Display Options
    @AppStorage(UserDefaultsKeys.studentsViewSortOrder) var studentsSortOrderRaw: String = "alphabetical"
    @AppStorage(UserDefaultsKeys.studentsViewSelectedFilter) var studentsFilterRaw: String = "all"
    @AppStorage(UserDefaultsKeys.studentsViewStyle) var studentsViewStyleRaw: String = "grid"
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // MARK: - State
    @State var searchText: String = ""
    @State var showingAddStudent = false
    @State var showingRollover = false
    @State var selectedStudentID: UUID?
    @State var isWithdrawnExpanded = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #if os(macOS)
    /// The Mac workspace treats withdrawn students as a collection, not an
    /// afterthought at the bottom of a roster list. iPhone and iPad retain the
    /// existing collapsible section.
    @State var isShowingWithdrawnRoster = false
    #endif

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

    var body: some View {
        Group {
            #if os(macOS)
            macWorkspace
            #else
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarColumn
            } detail: {
                detailColumn
            }
            .navigationSplitViewStyle(.balanced)
            #endif
        }
        .sheet(isPresented: $showingAddStudent) {
            AddStudentView()
                .presentationSizingFitted()
        }
        .sheet(isPresented: $showingRollover) {
            SchoolYearRolloverView()
                #if os(macOS)
                .frame(minWidth: 640, minHeight: 560)
                #endif
        }
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
        .onChange(of: appRouter.navigationDestination) { _, destination in
            handleNavigationDestinationChange(destination)
        }
        .task {
            refreshChangeTokens()
            ensureInitialManualOrderIfNeeded()
            loadDataOnDemand()
        }
        .onChange(of: studentsSortOrderRaw) { _, _ in
            reloadDataAsync()
        }
        .onChange(of: studentsFilterRaw) { _, _ in
            reloadDataAsync()
        }
        .onChange(of: attendanceChangeToken) { _, _ in
            reloadDataAsync()
        }
        .onChange(of: presentationChangeToken) { _, _ in
            reloadDataAsync()
        }
        .onChange(of: lessonChangeToken) { _, _ in
            reloadDataAsync()
        }
        // Debounce: many saves can fire in bursts (bulk edits, CloudKit merge
        // batches). Coalesce them so the three count() fetches in
        // refreshChangeTokens run once the dust settles, not per save.
        .onReceive(
            NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
                .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        ) { _ in
            refreshChangeTokens()
        }
        .onChange(of: uniqueStudentIDs) { _, _ in
            ensureInitialManualOrderIfNeeded()
            if viewModel.repairManualOrderUniquenessIfNeeded(uniqueStudents) {
                viewContext.safeSave()
            }
        }
    }

    // MARK: - Detail Column

    private var selectedStudent: CDStudent? {
        guard let id = selectedStudentID else { return nil }
        return uniqueStudents.first { $0.id == id }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let student = selectedStudent {
            StudentDetailView(student: student, isInline: true, onDone: { selectedStudentID = nil })
                .id(student.id)
                .navigationTitle(student.fullName)
                .inlineNavigationTitle()
                .toolbar { detailToolbar }
        } else {
            rosterBrowser
        }
    }

    #if os(macOS)
    /// The app already supplies the outer navigation split view. Using a
    /// second NavigationSplitView here makes macOS apply that outer sidebar's
    /// safe-area inset again, leaving a false blank column before the table.
    /// HSplitView provides the same user-resizable Mac workspace without
    /// nesting navigation containers.
    private var macWorkspace: some View {
        HSplitView {
            workspaceSidebarColumn

            macRosterColumn

            if selectedStudent != nil {
                macDetailColumn
                    .frame(minWidth: 480, idealWidth: 720)
            }
        }
        .navigationTitle(isShowingWithdrawnRoster ? "Former Students" : "Student Roster")
        .inlineNavigationTitle()
    }

    @ViewBuilder
    private var macRosterColumn: some View {
        StudentsTableView(
            students: macRosterStudents,
            nextLessonNames: viewModel.cachedNextLessonNames,
            lastObservationDates: viewModel.cachedLastObservationDates,
            presentNowIDs: presentNowIDs,
            selectedStudentID: $selectedStudentID
        )
        .frame(minWidth: 340, idealWidth: 520)
    }

    @ViewBuilder
    private var macDetailColumn: some View {
        if let student = selectedStudent {
            StudentDetailView(student: student, isInline: true, onDone: { selectedStudentID = nil })
                .id(student.id)
                .navigationTitle(student.fullName)
                .inlineNavigationTitle()
        } else {
            SelectStudentEmptyState()
                .navigationTitle("Student Record")
                .inlineNavigationTitle()
        }
    }

    var macRosterStudents: [CDStudent] {
        isShowingWithdrawnRoster ? withdrawnStudents : filteredStudents
    }

    #endif

    @ViewBuilder
    private var rosterBrowser: some View {
        #if os(iOS)
        if viewStyle == .grid {
            gridBrowser
        } else {
            SelectStudentEmptyState()
        }
        #else
        EmptyView()
        #endif
    }

    /// Full-width card grid shown in the compact detail area when nothing is
    /// selected. Sorting changes order, never the visual language of a child
    /// card; this keeps the roster calm and easy to scan.
    private var gridBrowser: some View {
        StudentsCardsGridView(
            students: filteredStudents,
            isBirthdayMode: false,
            isAgeMode: false,
            isManualMode: false,
            onTapStudent: { student in selectedStudentID = student.id },
            onReorder: { _, _, _, _ in }
        )
        .navigationTitle("Students")
        .inlineNavigationTitle()
    }

    @ToolbarContentBuilder
    private var detailToolbar: some ToolbarContent {
        if viewStyle == .grid {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    selectedStudentID = nil
                } label: {
                    Label("All Students", systemImage: "square.grid.2x2")
                }
                .help("Back to all students")
            }
        }
    }

    // MARK: - On-Demand Data Loading

    /// Loads attendance and lesson-age caches based on current filters
    private func loadDataOnDemand() {
        viewModel.loadDataOnDemand(
            viewContext: viewContext,
            calendar: calendar,
            students: uniqueStudents
        )
    }

    /// Helper to reload data asynchronously (reduces duplication in onChange handlers)
    private func reloadDataAsync() {
        Task { @MainActor in
            loadDataOnDemand()
        }
    }

    /// PERF: Lightweight change detection using fetchCount() instead of loading full tables.
    /// Called when SwiftData saves, so we detect inserts/deletes without materializing objects.
    private func refreshChangeTokens() {
        do {
            // Marking attendance usually edits an existing row (unmarked → present),
            // which leaves the count unchanged. Fold in the latest modifiedAt so a
            // status flip also reloads the Here filter.
            let attendanceCount = try viewContext.count(
                for: NSFetchRequest<CDAttendanceRecord>(entityName: "AttendanceRecord")
            )
            let latestRequest = NSFetchRequest<CDAttendanceRecord>(entityName: "AttendanceRecord")
            latestRequest.sortDescriptors = [NSSortDescriptor(key: "modifiedAt", ascending: false)]
            latestRequest.fetchLimit = 1
            let latestModified = try viewContext.fetch(latestRequest).first?.modifiedAt ?? .distantPast
            let attendanceToken = attendanceCount &+ Int(latestModified.timeIntervalSince1970 * 1000)
            if attendanceToken != attendanceChangeToken {
                attendanceChangeToken = attendanceToken
            }
            let presentationCount = try viewContext.count(
                for: NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment")
            )
            if presentationCount != presentationChangeToken {
                presentationChangeToken = presentationCount
            }
            let lessonCount = try viewContext.count(for: NSFetchRequest<CDLesson>(entityName: "Lesson"))
            if lessonCount != lessonChangeToken {
                lessonChangeToken = lessonCount
            }
        } catch {
            logger.warning("Failed to refresh change tokens: \(error)")
        }
    }

    private func ensureInitialManualOrderIfNeeded() {
        if viewModel.ensureInitialManualOrderIfNeeded(uniqueStudents) {
            viewContext.safeSave()
        }
    }

    private func assignManualOrder(from orderedIDs: [UUID]) {
        for (idx, id) in orderedIDs.enumerated() {
            if let s = uniqueStudents.first(where: { $0.id == id }) {
                s.manualOrder = Int64(idx)
            }
        }
    }

    func handleManualReorder(from source: IndexSet, to destination: Int) {
        guard sortOrder == .manual, let fromIndex = source.first else { return }
        let movingStudent = filteredStudents[fromIndex]
        let newAllIDs = viewModel.mergeReorderedSubsetIntoAll(
            movingID: movingStudent.id ?? UUID(),
            from: fromIndex,
            to: destination,
            current: filteredStudents,
            allStudents: uniqueStudents
        )
        assignManualOrder(from: newAllIDs)
        viewContext.safeSave()
    }

    // MARK: - Navigation Helpers

    private func handleNavigationDestinationChange(_ destination: AppRouter.NavigationDestination?) {
        guard let destination else { return }
        if case .newStudent = destination {
            showingAddStudent = true
            appRouter.clearNavigation()
        } else if case .importStudents = destination {
            showingStudentCSVImporter = true
            appRouter.clearNavigation()
        } else if case .openStudentDetail(let studentID) = destination {
            selectedStudentID = studentID
            appRouter.clearNavigation()
        }
    }
}
