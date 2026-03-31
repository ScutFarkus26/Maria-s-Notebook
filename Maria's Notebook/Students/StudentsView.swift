import CoreData
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let logger = Logger.students

// Top-level view for managing and browsing students with a unified sidebar.
// swiftlint:disable:next type_body_length
struct StudentsView: View {
    @Binding var mode: StudentMode

    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) var calendar
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    // OPTIMIZATION: Students always needed in roster mode, so keep @Query
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

    // OPTIMIZATION: Cache data loaded on-demand based on mode and filters (moved to ViewModel)
    @State var viewModel = StudentsViewModel()

    // MARK: - App Storage for Roster Mode
    @AppStorage(UserDefaultsKeys.studentsViewSortOrder) var studentsSortOrderRaw: String = "alphabetical"
    @AppStorage(UserDefaultsKeys.studentsViewSelectedFilter) var studentsFilterRaw: String = "all"
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames) var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // MARK: - State for Roster Mode
    @State var searchText: String = ""
    @State var showingAddStudent = false
    @State var selectedStudentID: UUID?
    @State var selectedStudentForSheet: CDStudent?
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
        case .age, .birthday:
            rosterGridContent
        case .roster, .withdrawn:
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
            if shouldUseGridView {
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
                    .inlineNavigationTitle()
                }
            } else if mode == .roster || mode == .withdrawn {
                // Three-pane layout for Roster/Withdrawn mode
                if horizontalSizeClass == .compact {
                    // iPhone: Use single pane with sheet for details
                    NavigationStack {
                        VStack(spacing: 0) {
                            SearchField("Search students", text: $searchText)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .onSubmit {
                                    if let first = filteredStudents.first {
                                        selectedStudentForSheet = first
                                    }
                                }
                            rosterListContent
                        }
                        .navigationTitle("Students")
                        .inlineNavigationTitle()
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
                        .inlineNavigationTitle()
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
                refreshChangeTokens()
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
            .onChange(of: attendanceChangeToken) { _, _ in
                reloadDataAsync()
            }
            .onChange(of: presentationChangeToken) { _, _ in
                reloadDataAsync()
            }
            .onChange(of: lessonChangeToken) { _, _ in
                reloadDataAsync()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)) { _ in
                refreshChangeTokens()
            }
            .onChange(of: uniqueStudentIDs) { _, _ in
                ensureInitialManualOrderIfNeeded()
                if viewModel.repairManualOrderUniquenessIfNeeded(uniqueStudents) {
                    do {
                        try viewContext.save()
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
            viewContext: viewContext,
            calendar: calendar,
            students: uniqueStudents
        )
    }

    /// Helper to reload data asynchronously (reduces duplication in onChange handlers)
    private func reloadDataAsync() {
        Task { @MainActor in
            await loadDataOnDemand()
        }
    }

    /// PERF: Lightweight change detection using fetchCount() instead of loading full tables.
    /// Called when SwiftData saves, so we detect inserts/deletes without materializing objects.
    private func refreshChangeTokens() {
        do {
            let attendanceCount = try viewContext.count(for: NSFetchRequest<CDAttendanceRecord>(entityName: "CDAttendanceRecord"))
            if attendanceCount != attendanceChangeToken {
                attendanceChangeToken = attendanceCount
            }
            let presentationCount = try viewContext.count(for: NSFetchRequest<CDLessonAssignment>(entityName: "CDLessonAssignment"))
            if presentationCount != presentationChangeToken {
                presentationChangeToken = presentationCount
            }
            let lessonCount = try viewContext.count(for: NSFetchRequest<CDLesson>(entityName: "CDLesson"))
            if lessonCount != lessonChangeToken {
                lessonChangeToken = lessonCount
            }
        } catch {
            logger.warning("Failed to refresh change tokens: \(error)")
        }
    }

    private func ensureInitialManualOrderIfNeeded() {
        if viewModel.ensureInitialManualOrderIfNeeded(uniqueStudents) {
            do {
                try viewContext.save()
            } catch {
                logger.warning("Failed to save initial manual order: \(error)")
            }
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
        guard effectiveSortOrder == .manual, let fromIndex = source.first else { return }
        let movingStudent = filteredStudents[fromIndex]
        let newAllIDs = viewModel.mergeReorderedSubsetIntoAll(
            movingID: movingStudent.id ?? UUID(),
            from: fromIndex,
            to: destination,
            current: filteredStudents,
            allStudents: uniqueStudents
        )
        assignManualOrder(from: newAllIDs)
        do {
            try viewContext.save()
        } catch {
            logger.warning("Failed to save manual reorder: \(error)")
        }
    }

    // MARK: - Navigation and Lifecycle Helpers

    private func handleNavigationDestinationChange(_ destination: AppRouter.NavigationDestination?) {
        guard let destination else { return }
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
        let specialModes: [StudentMode] = [.age, .birthday]
        let specialSortOrders = ["age", "birthday"]

        // Automatically set sort order and filter when switching modes
        switch newMode {
        case .age:
            studentsSortOrderRaw = "age"
        case .birthday:
            studentsSortOrderRaw = "birthday"
        case .withdrawn:
            studentsFilterRaw = "withdrawn"
            studentsSortOrderRaw = "alphabetical"
        case .roster where specialModes.contains(oldMode) && specialSortOrders.contains(studentsSortOrderRaw):
            // When switching back to roster from special modes, default to alphabetical
            studentsSortOrderRaw = "alphabetical"
        case .roster where oldMode == .withdrawn:
            // When switching back from withdrawn mode, reset filter to all
            studentsFilterRaw = "all"
        default:
            break
        }

        reloadDataAsync()
    }
}
