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

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)],
        predicate: NSPredicate(format: "statusRaw != %@", "complete")
    )
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

    @AppStorage(UserDefaultsKeys.generalShowTestStudents) var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    @AppStorage(UserDefaultsKeys.workAgendaHideScheduled) var hideScheduled: Bool = false
    @AppStorage(UserDefaultsKeys.workAgendaVisibleKinds)
    var visibleKindsRaw: String = WorkKind.allCases.map(\.rawValue).joined(separator: ",")
    @SceneStorage("LessonsAndWork.scope")
    var workspaceScopeRaw: String = LessonsAndWorkScope.needsAttention.rawValue

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
    #if os(macOS)
    @State var isCalendarMinimized: Bool = false
    #else
    @State var isCalendarMinimized: Bool = true
    #endif
    @State var calendarStartDate: Date = AppCalendar.startOfDay(Date())

    @State var selected: SelectionToken?
    @State var selectedLessonAssignment: CDLessonAssignment?
    @State var focusedPresentationID: UUID?
    @State var focusedWorkID: UUID?

    struct SelectionToken: Identifiable, Equatable { let id: UUID; let workID: UUID }

    // MEMORY OPTIMIZATION: Load lessons and students on-demand based on contracts
    var lessonsByID: [UUID: CDLesson] { lessonsByIDCache }
    var studentsByID: [UUID: CDStudent] { studentsByIDCache }

    var workspaceScope: LessonsAndWorkScope {
        LessonsAndWorkScope.resolved(rawValue: workspaceScopeRaw)
    }

    var workspaceScopeBinding: Binding<LessonsAndWorkScope> {
        Binding(
            get: { workspaceScope },
            set: { newValue in
                workspaceScopeRaw = newValue.rawValue
                focusedPresentationID = nil
                focusedWorkID = nil
                #if os(iOS)
                isCalendarMinimized = true
                #endif
            }
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
            refreshChangeTokens()
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
        VSplitView {
            workspaceWorkbench
                .frame(minHeight: 300)

            if workspaceScope != .history && !isCalendarMinimized {
                sharedAgendaPane
                    .frame(minHeight: 190, idealHeight: 300)
            }
        }
        #else
        VStack(spacing: 0) {
            mobileHeader
            Divider()

            if workspaceScope != .history && !isCalendarMinimized {
                sharedAgendaPane
            } else {
                workspaceWorkbench
            }
        }
        #endif
    }

    @ViewBuilder
    private var workspaceWorkbench: some View {
        switch workspaceScope {
        case .needsAttention:
            LessonsAndWorkAttentionView(
                openWork: Array(openWork).uniqueByID,
                scheduledCheckIns: Array(scheduledCheckIns).uniqueByID,
                lessonsByID: lessonsByID,
                studentsByID: studentsByID,
                searchText: debouncedSearchText,
                focusedPresentationID: focusedPresentationID,
                focusedWorkID: focusedWorkID,
                onOpenPresentation: openPresentation,
                onOpenWork: openDetail
            )

        case .upcoming:
            PresentationsView(
                isEmbedded: true,
                embeddedSearchText: debouncedSearchText,
                focusedPresentationID: focusedPresentationID
            )

        case .childrenWorking:
            openWorkPane

        case .history:
            LessonsAndWorkHistoryView(
                searchText: debouncedSearchText,
                focusedPresentationID: focusedPresentationID,
                focusedWorkID: focusedWorkID
            )
        }
    }

    private var openWorkPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(macOS)
            WorkKindFilterChipBar(visibleKinds: visibleKinds)
                .padding(.vertical, 4)
                .padding(.horizontal, 16)
            Divider()
            #endif

            OpenWorkGrid(
                works: openWorksFiltered(),
                lessonsByID: lessonsByID,
                studentsByID: studentsByID,
                sortMode: sortMode,
                focusedWorkID: focusedWorkID,
                onOpen: openDetail,
                onMarkCompleted: markCompleted,
                onScheduleToday: scheduleToday
            )
        }
    }

    private var sharedAgendaPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    moveCalendarStart(bySchoolDays: -UIConstants.planningNavigationStepSchoolDays)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text("Agenda")
                    .font(.title3.weight(.semibold))

                Button {
                    moveCalendarStart(bySchoolDays: UIConstants.planningNavigationStepSchoolDays)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Today") {
                    calendarStartDate = AppCalendar.startOfDay(Date())
                }
                .font(AppTheme.ScaledFont.captionSemibold)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            WorkAgendaCalendarPane(
                startDate: calendarStartDate,
                daysCount: 10,
                onOpenWork: openWork(id:),
                onOpenPresentation: openPresentation
            )
            .frame(maxHeight: .infinity)
        }
    }

    private var searchPrompt: String {
        switch workspaceScope {
        case .needsAttention: "Search children, lessons, or work"
        case .upcoming: "Search upcoming lessons or children"
        case .childrenWorking: "Search work, children, or lessons"
        case .history: "Search presentations or completed work"
        }
    }

    private func consumeWorkspaceRequestIfNeeded() {
        guard let request = appRouter.consumeLessonsAndWorkRequest() else { return }
        workspaceScopeRaw = request.scope.rawValue
        focusedPresentationID = request.presentationID
        focusedWorkID = request.workID
        #if os(iOS)
        isCalendarMinimized = true
        #endif
    }

    private func openPresentation(_ assignment: CDLessonAssignment) {
        #if os(macOS)
        guard let id = assignment.id else { return }
        openWindow(id: "PresentationDetailWindow", value: id)
        #else
        selectedLessonAssignment = assignment
        #endif
    }

    private func openWork(id: UUID) {
        guard let work = fetchWork(id: id) else { return }
        openDetail(work)
    }

    #if os(macOS)
    @ToolbarContentBuilder
    private var lessonsAndWorkToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("View", selection: workspaceScopeBinding) {
                ForEach(LessonsAndWorkScope.allCases) { scope in
                    Text(scope.title).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 500, idealWidth: 620)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            if workspaceScope == .childrenWorking {
                Button {
                    appRouter.requestNewWork()
                } label: {
                    Label("New Work", systemImage: "plus")
                }

                Picker("Sort", selection: $sortMode) {
                    ForEach(WorkAgendaSortMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Button {
                    hideScheduled.toggle()
                } label: {
                    Label(
                        hideScheduled ? "Show Scheduled Work" : "Hide Scheduled Work",
                        systemImage: hideScheduled ? "calendar.badge.minus" : "calendar"
                    )
                }
                .help(hideScheduled ? "Show scheduled work" : "Hide scheduled work")
            }

            if workspaceScope != .history {
                Button {
                    isCalendarMinimized.toggle()
                } label: {
                    Label(
                        isCalendarMinimized ? "Show Agenda" : "Hide Agenda",
                        systemImage: isCalendarMinimized ? "calendar" : "calendar.badge.minus"
                    )
                }
                .help(isCalendarMinimized ? "Show the shared agenda" : "Hide the shared agenda")
            }

            if workspaceScope == .childrenWorking {
                Menu("Output", systemImage: "square.and.arrow.up") {
                    Button("Print", systemImage: "printer") {
                        printWorkView()
                    }
                    Button("Export PDF", systemImage: "arrow.down.doc") {
                        exportWorkPDF()
                    }
                }
            }
        }
    }
    #endif

    @ViewBuilder
    private func sheetContent(for token: SelectionToken) -> some View {
        let work = fetchWork(id: token.workID)
        if let w = work {
            WorkDetailView(workID: w.id ?? UUID())
                .id(token.id)
        } else {
            ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
        }
    }

    private func fetchWork(id: UUID) -> CDWorkModel? {
        let request: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return viewContext.safeFetch(request).first
    }

    private var mobileHeader: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Lessons & Work") {
                HStack(spacing: 12) {
                    Menu {
                        ForEach(LessonsAndWorkScope.allCases) { scope in
                            Button {
                                workspaceScopeBinding.wrappedValue = scope
                            } label: {
                                if scope == workspaceScope {
                                    Label(scope.title, systemImage: "checkmark")
                                } else {
                                    Label(scope.title, systemImage: scope.systemImage)
                                }
                            }
                        }
                    } label: {
                        Label(workspaceScope.compactTitle, systemImage: workspaceScope.systemImage)
                    }

                    if workspaceScope != .history {
                    Button {
                        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            isCalendarMinimized.toggle()
                        }
                    } label: {
                        Image(systemName: isCalendarMinimized ? "calendar" : "calendar.badge.minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.primary.opacity(UIConstants.OpacityConstants.light))
                            .clipShape(Circle())
                    }
                    }

                    if workspaceScope == .childrenWorking {
                        Button {
                            appRouter.requestNewWork()
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(searchPrompt, text: $searchText)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        searchDebounceTask?.cancel()
                        debouncedSearchText = searchText
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(UIConstants.OpacityConstants.trace))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal, 16)
            .padding(.bottom, 4)
            if workspaceScope == .childrenWorking {
                WorkKindFilterChipBar(visibleKinds: visibleKinds)
                    .padding(.bottom, 4)
            }
        }
    }
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
