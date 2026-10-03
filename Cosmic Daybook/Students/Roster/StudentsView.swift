import Combine
import CoreData
import OSLog
import SwiftUI
import UniformTypeIdentifiers

// Top-level view for managing and browsing students.
//
// - iPhone and iPad: a NavigationSplitView. The sidebar is the roster (search,
//   scope chips with counts, rows grouped by level, a collapsible Former
//   Students section); the detail is the selected child's record, or on iPad
//   the class at a glance when nobody is selected.
// - Mac: a resizable two-pane workspace — the roster table under a scope bar,
//   and beside it the record or the class at a glance.
//
// Every row shows the same signals in every sort (`RosterSignals`); the sort
// only orders.
struct StudentsView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.calendar) var calendar
    @Environment(\.dependencies) var dependencies
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    /// Every student once, from the workspace's live roster (`RosterStore`
    /// already drops CloudKit duplicate-ID artifacts).
    var uniqueStudents: [CDStudent] { dependencies.roster.all }
    var uniqueStudentIDs: [UUID] { uniqueStudents.compactMap(\.id) }

    @State var viewModel = StudentsViewModel()

    // MARK: - Persisted Display Options
    @AppStorage(UserDefaultsKeys.studentsViewSortOrder) var studentsSortOrderRaw: String = "alphabetical"
    @AppStorage(UserDefaultsKeys.studentsViewSelectedFilter) var studentsFilterRaw: String = "all"
    @TestStudentVisibility var testStudents

    // MARK: - State
    @State var searchText: String = ""
    @State var showingAddStudent = false
    @State var showingRollover = false
    @State var selectedStudentID: UUID?
    @State var isWithdrawnExpanded = false
    @State var rosterSheet: RosterSheet?
    /// The sheet `rosterSheet` held, for its `onDismiss` (which runs after it is cleared).
    @State private var lastRosterSheet: RosterSheet?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    #if os(macOS)
    /// The Mac table shows former students in place of the class, chosen
    /// from the scope bar. iPhone and iPad keep a collapsible section.
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

    /// A quick action started from a roster row.
    enum RosterSheet: Identifiable {
        case observe(UUID)
        case lessonDraft(UUID)

        var id: String {
            switch self {
            case .observe(let id): return "observe-\(id)"
            case .lessonDraft(let id): return "lesson-\(id)"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        // Derived once per render; every pane reads this one snapshot.
        let snapshot = makeSnapshot()
        Group {
            #if os(macOS)
            macWorkspace(snapshot)
            #else
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebarColumn(snapshot)
            } detail: {
                detailColumn(snapshot)
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
        .sheet(item: $rosterSheet, onDismiss: discardEmptyLessonDraft) { sheet in
            switch sheet {
            case .observe(let studentID):
                QuickNoteSheet(initialStudentID: studentID)
            case .lessonDraft(let draftID):
                PresentationDraftSheet(id: draftID) { rosterSheet = nil }
                    .largeSheetSizing()
            }
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
        .onAppear {
            ensureInitialManualOrderIfNeeded()
            refreshSignals()
            // A request made before this tab first appeared (a Handoff from
            // another device switches to it and asks in one step).
            handleNavigationDestinationChange(appRouter.navigationDestination)
        }
        // Debounce: saves arrive in bursts (bulk edits, CloudKit merge
        // batches). Saves touching nothing a signal is read from (work,
        // todos, sync bookkeeping) are dropped first. The view model then
        // reloads only what moved: an attendance tap reloads attendance alone.
        // Only while on screen: a TabView keeps this tab alive behind the
        // others, and `onAppear` catches up on return.
        .onReceiveWhenVisible(Self.signalChanges(), catchUpOnAppear: false) {
            refreshSignals()
        }
        // Left open overnight (a Mac), today's marks, birthdays and counts
        // move to the new day; the view model's day stamp makes this a rebuild.
        .onCalendarDayChange { refreshSignals() }
        .onChange(of: uniqueStudentIDs) { _, _ in
            ensureInitialManualOrderIfNeeded()
            if viewModel.repairManualOrderUniquenessIfNeeded(uniqueStudents) {
                dependencies.saveCoordinator.save(viewContext, reason: "Repair student order")
            }
        }
    }

    // MARK: - Detail Column (iPhone, iPad)

    var selectedStudent: CDStudent? {
        guard let id = selectedStudentID else { return nil }
        return dependencies.roster.student(id: id)
    }

    @ViewBuilder
    private func detailColumn(_ snapshot: RosterSnapshot) -> some View {
        if let student = selectedStudent {
            studentRecord(student)
                .navigationTitle(student.fullName)
                .inlineNavigationTitle()
                .toolbar {
                    // On iPhone the record is pushed, and Back already does this.
                    if showsGlance {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                selectedStudentID = nil
                            } label: {
                                Label("Class at a Glance", systemImage: "rectangle.grid.1x2")
                            }
                            .help("Back to the class at a glance")
                        }
                    }
                }
        } else {
            classGlance(snapshot)
                .navigationTitle("Class at a Glance")
                .inlineNavigationTitle()
        }
    }

    /// Whether the detail column can show the class at a glance (regular width).
    private var showsGlance: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

    func studentRecord(_ student: CDStudent) -> some View {
        StudentDetailView(student: student, isInline: true, onDone: { selectedStudentID = nil })
            // The object, not the UUID: when a student leaves the classroom share her
            // row is replaced by a copy with the same id (`ClassroomShareRelease`), and a
            // view kept for the old object would read a deleted row.
            .id(student.objectID)
    }

    func classGlance(_ snapshot: RosterSnapshot) -> some View {
        ClassGlanceView(
            glance: ClassGlance.make(
                students: snapshot.enrolled,
                signals: { viewModel.signals(for: $0) },
                attendanceTaken: viewModel.attendanceTaken,
                calendar: calendar
            ),
            onSelect: { selectedStudentID = $0 },
            onShowScope: { filter in
                #if os(macOS)
                isShowingWithdrawnRoster = false
                #endif
                studentsFilterRaw = filter.storageValue
            }
        )
    }

    // MARK: - Signals

    /// Saves and imports that can move a roster signal.
    private static func signalChanges() -> some Publisher<Void, Never> {
        let center = NotificationCenter.default
        let saves = center.publisher(for: .NSManagedObjectContextDidSave)
            // @Sendable: runs on the saving context's queue (see onPresentationDataChange).
            .filter { @Sendable note in saveTouchesSignals(note.userInfo) }
            .map { @Sendable _ in () }
        let imports = center.publisher(for: .presentationDataDidChange)
            .filter { @Sendable note in
                let key = PersistentHistoryProcessor.changedEntityNamesKey
                guard let changed = note.userInfo?[key] as? Set<String> else { return true }
                return !changed.isDisjoint(with: StudentsViewModel.signalInputEntities)
            }
            .map { @Sendable _ in () }
        return saves.merge(with: imports)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
    }

    func refreshSignals() {
        viewModel.refreshIfNeeded(viewContext: viewContext, calendar: calendar, students: uniqueStudents)
    }

    // MARK: - Row Actions

    func addObservation(for student: CDStudent) {
        guard let id = student.id else { return }
        rosterSheet = .observe(id)
    }

    /// Opens a new presentation with this child already on it, the lesson
    /// picker focused — the same draft the toolbar's New Presentation makes.
    func giveLesson(to student: CDStudent) {
        guard let studentID = student.id else { return }
        let draft = PresentationFactory.makeDraft(lessonID: UUID(), studentIDs: [studentID], context: viewContext)
        dependencies.saveCoordinator.save(viewContext, reason: "Create presentation draft")
        if let draftID = draft.id {
            rosterSheet = .lessonDraft(draftID)
            lastRosterSheet = rosterSheet
        }
    }

    /// The draft closed before a lesson was picked is removed. The draft
    /// sheet only removes one with no children, and this one starts with a child.
    private func discardEmptyLessonDraft() {
        guard case .lessonDraft(let draftID)? = lastRosterSheet else { return }
        lastRosterSheet = nil
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id == %@", draftID as CVarArg)
        guard let draft = viewContext.safeFetch(request).first,
              draft.state == .draft, draft.lesson == nil else { return }
        viewContext.delete(draft)
        dependencies.saveCoordinator.save(viewContext, reason: "Discard empty presentation draft")
    }

    // MARK: - Manual Order

    private func ensureInitialManualOrderIfNeeded() {
        if viewModel.ensureInitialManualOrderIfNeeded(uniqueStudents) {
            dependencies.saveCoordinator.save(viewContext, reason: "Initialize student order")
        }
    }

    private func assignManualOrder(from orderedIDs: [UUID]) {
        for (idx, id) in orderedIDs.enumerated() {
            dependencies.roster.student(id: id)?.moveInRoster(to: Int64(idx))
        }
    }

    /// Moves a child within `subset`, the rows of one level section.
    func handleManualReorder(from source: IndexSet, to destination: Int, in subset: [CDStudent]) {
        guard sortOrder == .manual, let fromIndex = source.first, subset.indices.contains(fromIndex) else { return }
        let movingStudent = subset[fromIndex]
        let newAllIDs = viewModel.mergeReorderedSubsetIntoAll(
            movingID: movingStudent.id ?? UUID(),
            from: fromIndex,
            to: destination,
            current: subset,
            allStudents: uniqueStudents
        )
        assignManualOrder(from: newAllIDs)
        dependencies.saveCoordinator.save(viewContext, reason: "Reorder students")
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

private extension CDStudent {
    /// The guide's reorder: a child whose place changed is stamped as edited (`modifiedAt`).
    func moveInRoster(to order: Int64) {
        guard manualOrder != order else { return }
        manualOrder = order
        modifiedAt = Date()
    }
}
