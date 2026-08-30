// WorksAgendaView.swift
// Shared Lessons & Work workspace for the full presentation-to-practice cycle.
//
// Helpers live in:
// - WorksAgendaView+DataHelpers.swift  (cache loading, filtering, display helpers)
// - WorksAgendaView+Actions.swift      (calendar navigation, work item actions)

import Combine
import CoreData
import OSLog
import SwiftUI
#if os(macOS)
import AppKit
import UniformTypeIdentifiers
import PDFKit
#endif

struct WorksAgendaView: View {
    static let logger = Logger.work

    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.calendar) var calendar
    @Environment(\.appRouter) var appRouter
    @Environment(SaveCoordinator.self) var saveCoordinator
    @Environment(RestoreCoordinator.self) private var restoreCoordinator
    #if os(macOS)
    @Environment(\.openWindow) var openWindow
    #endif

    // Prefetch the two relationships `LessonsAndWorkTriage` reads for every row
    // (scheduled check-ins, and the notes behind last-meaningful-touch). Without
    // this, triaging a classroom's worth of open work faults them one row at a
    // time — the same N+1 that `WorksLogView` already prefetches away.
    @FetchRequest(fetchRequest: {
        let request = NSFetchRequest<CDWorkModel>(entityName: "WorkModel")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)]
        request.predicate = NSPredicate(format: "statusRaw != %@", "complete")
        request.relationshipKeyPathsForPrefetching = ["checkIns", "unifiedNotes"]
        return request
    }())
    var openWork: FetchedResults<CDWorkModel>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkCheckIn.date, ascending: true)],
        predicate: NSPredicate(format: "statusRaw == %@", "Scheduled")
    )
    var scheduledCheckIns: FetchedResults<CDWorkCheckIn>

    // PERF: Use lightweight count-based change detection instead of loading full tables.
    @State var lessonChangeToken: Int = 0
    @State var studentChangeToken: Int = 0

    // Lazy-loaded caches (only populated when needed)
    @State var lessonsByIDCache: [UUID: CDLesson] = [:]
    @State var studentsByIDCache: [UUID: CDStudent] = [:]

    /// Every record on screen, triaged once. The Attention list reads it, the
    /// card badges read it, and the picker's counts will. Rebuilt on the same
    /// debounced path as the caches below — never in a `body` pass, because
    /// placing one work item walks its check-ins and notes and then counts
    /// school days.
    @State var partition = LessonsAndWorkPartition()

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @AppStorage(UserDefaultsKeys.workAgendaHideScheduled) var hideScheduled: Bool = false
    @AppStorage(UserDefaultsKeys.workAgendaVisibleKinds)
    var visibleKindsRaw: String = WorkKind.allCases.map(\.rawValue).joined(separator: ",")
    /// Which half of the workspace is showing. Same storage key as the old
    /// state-first picker, so a scene saved under it migrates through
    /// `WorkspaceKind.resolved` rather than snapping back to a default.
    @SceneStorage("LessonsAndWork.scope")
    var workspaceKindRaw: String = WorkspaceKind.presentations.rawValue
    /// Which state pill the Work half is filtered by.
    @SceneStorage("LessonsAndWork.workChip")
    var workChipRaw: String = WorkFilterChip.needsChecking.rawValue

    var visibleKinds: Binding<Set<WorkKind>> {
        Binding(
            get: {
                let parsed = visibleKindsRaw
                    .split(separator: ",")
                    .compactMap { WorkKind(rawValue: String($0)) }
                let set = Set(parsed)
                return set.isEmpty ? Set(WorkKind.allCases) : set
            },
            set: { newValue in
                let safe = newValue.isEmpty ? Set(WorkKind.allCases) : newValue
                visibleKindsRaw = WorkKind.allCases
                    .filter { safe.contains($0) }
                    .map(\.rawValue)
                    .joined(separator: ",")
            }
        )
    }

    @State var sortMode: WorkAgendaSortMode = .student
    @State var searchText: String = ""
    @State var debouncedSearchText: String = ""
    @State var searchDebounceTask: Task<Void, Never>?
    /// Command-click selections, one per half so switching sides does not
    /// silently carry a selection of presentations into a bulk work action.
    @State var presentationSelection = WorkspaceMultiSelection()
    @State var workSelection = WorkspaceMultiSelection()
    @AppStorage(UserDefaultsKeys.workAgendaCalendarExpanded) var isCalendarExpanded: Bool = true
    @AppStorage(UserDefaultsKeys.workAgendaCalendarFraction) var calendarFraction: Double = 0.42
    /// The share while a drag is in flight, so the pane tracks the finger
    /// without writing to storage on every frame.
    @State var liveCalendarFraction: Double?
    @State var calendarResizeStartFraction: Double?

    @State var selected: SelectionToken?
    @State var selectedLessonAssignment: CDLessonAssignment?
    @State var focusedPresentationID: UUID?
    @State var focusedWorkID: UUID?

    struct SelectionToken: Identifiable, Equatable { let id: UUID; let workID: UUID }

    // MEMORY OPTIMIZATION: Load lessons and students on-demand based on contracts
    var lessonsByID: [UUID: CDLesson] { lessonsByIDCache }
    var studentsByID: [UUID: CDStudent] { studentsByIDCache }

    var workspaceKind: WorkspaceKind {
        WorkspaceKind.resolved(rawValue: workspaceKindRaw)
    }

    var workspaceKindBinding: Binding<WorkspaceKind> {
        Binding(
            get: { workspaceKind },
            set: { newValue in
                workspaceKindRaw = newValue.rawValue
                focusedPresentationID = nil
                focusedWorkID = nil
            }
        )
    }

    var workChip: WorkFilterChip {
        WorkFilterChip.resolved(rawValue: workChipRaw)
    }

    var workChipBinding: Binding<WorkFilterChip> {
        Binding(
            get: { workChip },
            set: { workChipRaw = $0.rawValue }
        )
    }

    /// Combined trigger for data reload — changes when any relevant data changes
    private var dataReloadTrigger: Int {
        var hasher = Hasher()
        hasher.combine(openWork.count)
        hasher.combine(lessonChangeToken)
        hasher.combine(studentChangeToken)
        hasher.combine(showTestStudents)
        hasher.combine(testStudentNamesRaw)
        return hasher.finalize()
    }

    var body: some View {
        Group {
            if restoreCoordinator.isRestoring {
                VStack(spacing: 16) {
                    ProgressView().controlSize(.large)
                    Text("Restoring data…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                workspaceContent
                .navigationTitle("Lessons & Work")
                #if os(macOS)
                .searchable(text: $searchText, placement: .toolbar, prompt: searchPrompt)
                .toolbar { lessonsAndWorkToolbarContent }
                #endif
                .sheet(
                    item: $selected,
                    onDismiss: { selected = nil },
                    content: { token in sheetContent(for: token) }
                )
                #if os(iOS)
                .sheet(item: $selectedLessonAssignment) { assignment in
                    PresentationDetailView(lessonAssignment: assignment) {
                        selectedLessonAssignment = nil
                    }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                }
                #endif
            }
        }
        .onAppear {
            refreshChangeTokens()
            loadLessonsAndStudentsIfNeeded()
            consumeWorkspaceRequestIfNeeded()
        }
        .onChange(of: dataReloadTrigger) { _, _ in
            loadLessonsAndStudentsIfNeeded()
        }
        // Debounce: saves arrive in bursts (bulk edits, CloudKit merge batches).
        // Coalesce them so the change-token fetches run once the dust settles,
        // not once per save (same pattern as StudentsView).
        .onReceive(
            NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave)
                .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        ) { _ in
            refreshAfterSave()
        }
        .onChange(of: searchText) { _, newValue in
            searchDebounceTask?.cancel()
            searchDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled else { return }
                debouncedSearchText = newValue
            }
        }
        .onChange(of: appRouter.lessonsAndWorkRequest?.id) { _, _ in
            consumeWorkspaceRequestIfNeeded()
        }
        .onDisappear {
            searchDebounceTask?.cancel()
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        #if os(macOS)
        workspaceSplit
        #else
        VStack(spacing: 0) {
            mobileHeader
            Divider()
            workspaceSplit
        }
        #endif
    }

    /// The half the guide is working in. Scheduled is neither of them — it is
    /// the pane underneath, because a schedule is a destination, not a peer
    /// list you switch to.
    @ViewBuilder
    var workspaceWorkbench: some View {
        switch workspaceKind {
        case .presentations:
            LessonsAndWorkPresentationsView(
                searchText: debouncedSearchText,
                focusedPresentationID: focusedPresentationID,
                selection: presentationSelection,
                studentIDsWithUpcomingLessons: studentIDsWithUpcomingLessons
            )

        case .work:
            LessonsAndWorkWorkView(
                split: partition.work,
                visibleWorkIDs: visibleWorkIDs,
                lessonsByID: lessonsByID,
                studentsByID: studentsByID,
                attentionWorkIDs: attentionWorkIDs,
                sortMode: sortMode,
                searchText: debouncedSearchText,
                focusedWorkID: focusedWorkID,
                selection: workSelection,
                chip: workChipBinding,
                visibleKinds: visibleKinds,
                onOpenWork: openDetail,
                onMarkCompleted: markCompleted,
                onScheduleToday: scheduleToday,
                onDeleted: refreshAfterSave
            )
        }
    }

    var searchPrompt: String { workspaceKind.searchPrompt }

    /// True when the work grid is on screen, and so its sort, kind chips and
    /// print/export controls apply.
    var showsWorkGrid: Bool { workspaceKind == .work }
}

#Preview {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext

    let s = CDStudent(context: ctx)
    s.firstName = "Ada"; s.lastName = "Lovelace"; s.birthday = Date(); s.level = .upper
    let l = CDLesson(context: ctx)
    l.name = "Long Division"; l.area = "Math"; l.sequence = "Ops"
    let w = CDWorkModel(context: ctx)
    w.status = .active; w.studentID = s.id?.uuidString ?? ""; w.lessonID = l.id?.uuidString ?? ""

    return WorksAgendaView()
        .previewEnvironment(using: stack)
        .environment(SaveCoordinator.preview)
}
