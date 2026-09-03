// RootView.swift
// App root container with top pill navigation and tab routing.
//
// Split into multiple files for maintainability:
// - RootView.swift (this file) - Main view structure and body
// - RootSidebar.swift - Sidebar navigation component
// - RootDetailContent.swift - Detail content routing
// - RootViewComponents.swift - Supporting components (QuickNoteGlassButton, warning banners)

import Combine
import SwiftUI
import CoreData
import OSLog
#if !os(macOS)
import TipKit
#endif

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

// Top-level container that manages app-wide navigation between Students, Albums, Planning, Today, Logs, and Settings.
// NavigationItem and Tab enums live in RootView+NavigationItem.swift.
// swiftlint:disable:next type_body_length
struct RootView: View {
    private static let logger = Logger.app_
    let classroomWorkspace: ClassroomWorkspaceStore

    // MARK: - Storage
    @SceneStorage("RootView.selectedNavItem") private var selectedNavItemRaw: String?
    @SceneStorage("RootView.selectedTab") private var selectedTabRaw: String?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.dependencies) private var dependencies
    @Environment(\.calendar) private var calendar
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let quickNoteTip = QuickNoteTip()
    #endif
    @State private var quickNoteParams: QuickNoteParams?
    @State private var isShowingCommandBar = false
    @State private var isShowingSearch = false
    @State private var focusedSearchAction = FocusedSearchAction()
    @State private var newPresentationDraftID: UUID?
    @State private var isShowingNewWorkItem = false
    @State private var isShowingRecordPractice = false
    @State private var isShowingNewTodo = false
    @State private var workDetailIDToOpen: UUID?
    @State private var selectedNavItem: NavigationItem = .today
    @State private var companionViewModel = NotebookCompanionViewModel()
    @AppStorage(UserDefaultsKeys.notebookCompanionVisible)
    private var isNotebookCompanionVisible = true
    @AppStorage(UserDefaultsKeys.notebookCompanionDetached)
    private var isNotebookCompanionDetached = false

    // Command bar pre-population state
    @State private var commandBarWorkLessonID: UUID?
    @State private var commandBarWorkStudentIDs: Set<UUID> = []
    @State private var commandBarTodoTitle: String = ""
    // Preferences for presentations preloading
    @AppStorage(UserDefaultsKeys.planningInboxOrder) private var inboxOrderRaw: String = ""
    @AppStorage(UserDefaultsKeys.lessonsAgendaMissWindow)
    private var missWindowRaw: String = PresentationsMissWindow.all.rawValue
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"
    
    private var missWindow: PresentationsMissWindow {
        PresentationsMissWindow(rawValue: missWindowRaw) ?? .all
    }

    // MARK: - Computed
    /// The raw value of a retired navigation item that pointed at the same
    /// workspace as `.planningAgenda`, opened on the children's-work lens. The
    /// case is gone; this keeps a device that last selected it landing where it
    /// expects instead of falling back to Today.
    private static let retiredOpenWorkNavItemRaw = "planningWork"

    /// The retired "Needs Lesson" destination. The list it showed — which
    /// children have waited longest — now lives beside the presentations in To
    /// Schedule, so a device restoring this selection lands there rather than
    /// falling through to Today.
    private static let retiredNeedsLessonNavItemRaw = "needsLesson"

    private func resolvedPersistedNavItem() -> NavigationItem {
        if let raw = selectedNavItemRaw {
            if raw == Self.retiredOpenWorkNavItemRaw {
                appRouter.lessonsAndWorkRequest = .init(scope: .attention)
                return .planningAgenda
            }
            if raw == Self.retiredNeedsLessonNavItemRaw {
                appRouter.lessonsAndWorkRequest = .init(scope: .toSchedule)
                return .planningAgenda
            }
            if let item = NavigationItem(rawValue: raw) {
                return item
            }
        }
        if let legacyRaw = selectedTabRaw, let legacyTab = Tab(rawValue: legacyRaw) {
            return resolvedLegacyTab(legacyTab)
        }
        return .today
    }

    /// Maps a selection saved by a build that still used the old `Tab` enum.
    private func resolvedLegacyTab(_ legacyTab: Tab) -> NavigationItem {
        guard legacyTab == .planning else {
            return NavigationItem(fromLegacyTab: legacyTab) ?? .today
        }
        guard let modeRaw = UserDefaults.standard.string(forKey: UserDefaultsKeys.planningRootViewMode) else {
            return .planningAgenda
        }
        switch modeRaw {
        case "Open Work":
            appRouter.lessonsAndWorkRequest = .init(scope: .attention)
            return .planningAgenda
        case "Projects": return .planningProjects
        case "Checklist": return .planningChecklist
        default:
            appRouter.lessonsAndWorkRequest = .init(scope: .toSchedule)
            return .planningAgenda
        }
    }

    // MARK: - Body
    var body: some View {
        rootWithQuickActions
        .sheet(item: $newPresentationDraftID) { draftID in
            PresentationDraftSheet(id: draftID) {
                newPresentationDraftID = nil
            }
            #if os(macOS)
            .frame(minWidth: UIConstants.SheetSize.large.width, minHeight: UIConstants.SheetSize.large.height)
            .presentationSizingFitted()
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(isPresented: $isShowingNewWorkItem) {
            QuickNewWorkItemSheet(
                preSelectedLessonID: commandBarWorkLessonID,
                preSelectedStudentIDs: commandBarWorkStudentIDs
            ) { workID in
                // Delay slightly to allow sheet dismiss animation to complete
                Task { @MainActor in
                    do {
                        try await Task.sleep(for: .milliseconds(300))
                    } catch {
                        Self.logger.warning("Failed to sleep before opening work detail: \(error)")
                    }
                    workDetailIDToOpen = workID
                }
            }
            .onDisappear {
                commandBarWorkLessonID = nil
                commandBarWorkStudentIDs = []
            }
        }
        .sheet(item: $workDetailIDToOpen) { workID in
            WorkDetailView(workID: workID, onDone: { workDetailIDToOpen = nil })
            #if os(macOS)
                .frame(minWidth: UIConstants.SheetSize.large.width, minHeight: UIConstants.SheetSize.large.height)
                .presentationSizingFitted()
            #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(isPresented: $isShowingRecordPractice) {
            RecordPracticeSheet()
            #if os(macOS)
                .frame(minWidth: UIConstants.SheetSize.large.width, minHeight: UIConstants.SheetSize.large.height)
                .presentationSizingFitted()
            #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(isPresented: $isShowingNewTodo) {
            NavigationStack {
                NewTodoForm(initialTitle: commandBarTodoTitle)
                    .navigationTitle("New Todo")
                    .inlineNavigationTitle()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                isShowingNewTodo = false
                            }
                        }
                    }
            }
            .onDisappear {
                commandBarTodoTitle = ""
            }
        }
        .sheet(isPresented: $isShowingSearch) {
            AppSearchView()
        }
        // Expose key-window actions to the menu bar (Find…, File > New quick-capture).
        // Only the key main window's RootView provides these, so menu commands act
        // on exactly one window and disable when no main window is frontmost.
        .focusedSceneValue(\.openSearch, focusedSearchAction)
        .onAppear {
            focusedSearchAction.setAction {
                isShowingSearch = true
            }
        }
        .onDisappear {
            focusedSearchAction.clearAction()
        }
        .focusedSceneValue(\.quickCapture, QuickCaptureActions(
            newPresentation: { createPresentationDraft() },
            recordPractice: { isShowingRecordPractice = true },
            newTodo: { isShowingNewTodo = true },
            newNote: { quickNoteParams = QuickNoteParams() }
        ))
    #if os(macOS)
        .background(
            EnsureResizableWindow(
                minSize: NSSize(
                    width: UIConstants.WindowSize.minWidth,
                    height: UIConstants.WindowSize.minHeight
                )
            )
        )
    #endif
    }

    // MARK: - View Components

    private var rootWithQuickActions: some View {
        rootLayoutWithObservers
        #if os(macOS)
        .toolbar { rootToolbar }
        #endif
        .saveErrorAlert()
        .toastOverlay(dependencies.toastService)
        #if !os(macOS)
        .overlay(alignment: .bottom) {
            TipView(quickNoteTip, arrowEdge: .bottom)
                .padding(.horizontal, 24)
                .padding(.bottom, 80)
        }
        #endif
        .overlay(alignment: .bottomTrailing) {
            if isNotebookCompanionVisible && !isNotebookCompanionDetached {
                QuickNoteGlassButton(
                    isShowingCommandBar: $isShowingCommandBar,
                    onNewPresentation: { createPresentationDraft() },
                    isShowingWorkItemSheet: $isShowingNewWorkItem,
                    onRecordPractice: {
                        isShowingRecordPractice = true
                    },
                    onNewTodo: {
                        isShowingNewTodo = true
                    },
                    onNewNote: {
                        quickNoteParams = QuickNoteParams()
                    },
                    companionSnapshot: companionViewModel.snapshot,
                    isAIWorking: appRouter.isAIWorking,
                    onAskAI: { prompt in
                        if let prompt {
                            appRouter.requestAIQuestion(prompt)
                        } else {
                            appRouter.navigateTo(.askAI)
                        }
                    },
                    onReviewTodos: {
                        appRouter.navigateTo(.todos)
                    },
                    onRefreshCompanion: {
                        companionViewModel.reload(calendar: calendar)
                    }
                )
            }
        }
        .sheet(item: $quickNoteParams) { params in
            QuickNoteSheet(
                initialStudentIDs: params.studentIDs,
                initialBodyText: params.bodyText,
                initialTags: params.tags
            )
        }
        .sheet(isPresented: $isShowingCommandBar) {
            CommandBarSheet(
                onPresentation: { draftID in
                    isShowingCommandBar = false
                    newPresentationDraftID = draftID
                },
                onWorkItem: { lessonID, studentIDs in
                    isShowingCommandBar = false
                    commandBarWorkLessonID = lessonID
                    commandBarWorkStudentIDs = studentIDs
                    isShowingNewWorkItem = true
                },
                onNote: { studentIDs, bodyText, inferredTags in
                    isShowingCommandBar = false
                    quickNoteParams = QuickNoteParams(
                        studentIDs: studentIDs,
                        bodyText: bodyText,
                        tags: inferredTags
                    )
                },
                onTodo: { titleText in
                    isShowingCommandBar = false
                    commandBarTodoTitle = titleText
                    isShowingNewTodo = true
                }
            )
        }
        .overlay {
            if classroomWorkspace.isPreparingSample {
                ZStack {
                    Color.black.opacity(0.08)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        Text("Preparing Sample Class…")
                            .font(.headline)
                        Text("Copying the lesson catalog into its separate local classroom.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(radius: 12)
                }
            }
        }
        .alert(
            "Couldn’t Open Sample Class",
            isPresented: Binding(
                get: { classroomWorkspace.preparationErrorMessage != nil },
                set: { isPresented in
                    if !isPresented { classroomWorkspace.dismissPreparationError() }
                }
            )
        ) {
            Button("OK") { classroomWorkspace.dismissPreparationError() }
        } message: {
            Text(classroomWorkspace.preparationErrorMessage ?? "The sample classroom could not be prepared.")
        }
        .alert(
            "The \(dependencies.schoolYearStore.current.label) School Year Has Begun",
            isPresented: Binding(
                get: { dependencies.schoolYearStore.needsCounterResetPrompt },
                set: { isPresented in
                    if !isPresented { dependencies.schoolYearStore.keepCountersRunning() }
                }
            )
        ) {
            Button("Start Fresh") { dependencies.schoolYearStore.startFreshCounters() }
            Button("Keep Counting", role: .cancel) { dependencies.schoolYearStore.keepCountersRunning() }
        } message: {
            Text(schoolYearResetPromptMessage)
        }
    }

    /// Explains what "start fresh" does before the guide commits to it: counters only, and
    /// nothing is moved or deleted.
    private var schoolYearResetPromptMessage: String {
        let start = dependencies.schoolYearStore.current.start
            .formatted(.dateTime.month(.wide).day().year())
        return "Restart the day counters — days since last lesson, days since last meeting, and "
            + "work aging — from \(start)? Last year's records stay exactly as they are."
    }

    private var rootLayoutWithObservers: some View {
        rootLayout
        .onAppear(perform: restoreSelectionIfNeeded)
        .task {
            companionViewModel.configure(context: viewContext)
            #if os(macOS)
            if isNotebookCompanionVisible && isNotebookCompanionDetached {
                openWindow(id: "notebookCompanion")
            }
            #endif
        }
        .onChange(of: isNotebookCompanionVisible) { _, isVisible in
            #if os(macOS)
            if isVisible && isNotebookCompanionDetached {
                openWindow(id: "notebookCompanion")
            } else if !isVisible {
                dismissWindow(id: "notebookCompanion")
            }
            #endif
        }
        // Debounce: objectsDidChange fires per change, not per save, so a single
        // CloudKit merge can post it hundreds of times — and each reload runs the
        // companion's count queries. Coalesce them (same pattern as StudentsView).
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: viewContext
            )
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        ) { _ in
            companionViewModel.reload(calendar: calendar)
        }
        .onCalendarDayChange {
            companionViewModel.reload(calendar: calendar)
        }
        .onChange(of: selectedNavItem) { _, item in
            persistSelection(item)
        }
        .onChange(of: appRouter.navigationDestination, handleNavigationDestinationChange)
        .onChange(of: appRouter.selectedNavItem, handleSelectedNavItemChange)
        .onChange(of: appRouter.triggerNewWorkItem) { _, value in
            guard value else { return }
            appRouter.triggerNewWorkItem = false
            isShowingNewWorkItem = true
        }
        .onChange(of: appRouter.triggerRecordPractice) { _, value in
            guard value else { return }
            appRouter.triggerRecordPractice = false
            isShowingRecordPractice = true
        }
        .onChange(of: appRouter.triggerNewPresentation) { _, value in
            guard value else { return }
            appRouter.triggerNewPresentation = false
            createPresentationDraft()
        }
        .onChange(of: appRouter.triggerCommandBar) { _, value in
            guard value else { return }
            appRouter.triggerCommandBar = false
            isShowingCommandBar = true
        }
    }

    /// Creates a presentation draft and opens its editor sheet. Shared by the
    /// iOS toolbar trigger, the radial quick-command menu, and File > New.
    private func createPresentationDraft() {
        let draft = PresentationFactory.makeDraft(lessonID: UUID(), studentIDs: [], context: viewContext)
        viewContext.safeSave()
        newPresentationDraftID = draft.id
    }

    @ViewBuilder private var rootLayout: some View {
        #if os(macOS)
        // The NavigationSplitView has to be the window's root content for macOS
        // to hand the titlebar inset to BOTH of its columns, so nothing may wrap
        // it here. The banners live inside the detail column instead — see
        // splitViewContent.
        mainContent
        #else
        let layout = VStack(spacing: 0) {
            warningBanners
            if horizontalSizeClass == .compact {
                mobileContextBar
            }
            Divider()
            mainContent
        }

        if horizontalSizeClass == .compact {
            layout
        } else {
            layout
                .overlay(alignment: .topTrailing) {
                    searchAndSyncOverlay
                }
        }
        #endif
    }

    #if os(iOS)
    private var mobileContextBar: some View {
        HStack(spacing: 10) {
            MobileClassroomAndYearPicker(
                workspaceStore: classroomWorkspace,
                showsContextLabel: true
            )

            Spacer(minLength: 8)

            Button {
                isShowingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")

            if !classroomWorkspace.isShowingSampleClass {
                CompactSyncStatusIndicator(compact: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
    #endif

    private var searchAndSyncOverlay: some View {
        HStack(spacing: 8) {
            ClassroomWorkspacePicker(workspaceStore: classroomWorkspace)
            SchoolYearPicker()
            Button {
                isShowingSearch = true
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Search")
            #if os(macOS)
            .help("Search notes, lessons, students, and todos (⌘F)")
            #endif
            if !classroomWorkspace.isShowingSampleClass {
                CompactSyncStatusIndicator(compact: true)
            }
        }
        .padding(.trailing, 12)
        .padding(.top, 6)
    }

    @ViewBuilder
    private var warningBanners: some View {
        if classroomWorkspace.isShowingSampleClass {
            SampleClassroomBanner(workspaceStore: classroomWorkspace)
        }

        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag) {
            EphemeralStoreWarningBanner()
        }

        let cloudStatus = CloudKitConfiguration.getCloudKitStatus()
        if !classroomWorkspace.isShowingSampleClass,
           cloudStatus.enabled && !cloudStatus.active {
            CloudKitSyncWarningBanner()
        }

        if !dependencies.schoolYearStore.isCurrentYearSelected {
            SchoolYearBanner()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        #if os(iOS)
        RootAdaptiveTabs(selectedNavItem: $selectedNavItem)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        // No .frame wrapper: every layer between the window root and the split
        // view is another chance for the titlebar inset to go missing.
        splitViewContent
        #endif
    }

    private var splitViewContent: some View {
        NavigationSplitView {
            RootSidebar(selection: $selectedNavItem)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            #if os(macOS)
            // Banners stack above the detail content rather than riding on the
            // split view as a safe-area inset: an inset wrapped around the
            // AppKit-backed split view never moves its columns, so the banner
            // drew on top of the first rows and the student record's header and
            // swallowed the clicks meant for their buttons.
            VStack(spacing: 0) {
                warningBanners
                RootDetailContent(selectedNavItem: selectedNavItem)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .navigationTitle(selectedNavItem.displayName)
            #else
            RootDetailContent(selectedNavItem: selectedNavItem)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationTitle(selectedNavItem.displayName)
            #endif
        }
    }

    #if os(macOS)
    @ToolbarContentBuilder
    private var rootToolbar: some ToolbarContent {
        ToolbarItem(id: "classroom", placement: .primaryAction) {
            ClassroomWorkspacePicker(workspaceStore: classroomWorkspace)
        }

        ToolbarItem(id: "schoolYear", placement: .primaryAction) {
            SchoolYearPicker()
        }

        ToolbarItem(id: "search", placement: .primaryAction) {
            Button {
                isShowingSearch = true
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search notes, lessons, students, and todos (⌘F)")
        }

        if !classroomWorkspace.isShowingSampleClass {
            ToolbarItem(id: "syncStatus", placement: .primaryAction) {
                CompactSyncStatusIndicator(compact: true)
            }
        }
    }
    #endif

    // MARK: - Event Handlers

    private func restoreSelectionIfNeeded() {
        let persistedSelection = resolvedPersistedNavItem()
        if selectedNavItem != persistedSelection {
            selectedNavItem = persistedSelection
        }
        persistSelection(persistedSelection)
    }

    private func persistSelection(_ item: RootView.NavigationItem) {
        let newValue = item.rawValue
        if selectedNavItemRaw != newValue {
            selectedNavItemRaw = newValue
        }
    }

    private func handleNavigationDestinationChange(
        _ oldValue: AppRouter.NavigationDestination?,
        _ destination: AppRouter.NavigationDestination?
    ) {
        if case .openAttendance = destination {
            if selectedNavItem != .attendance {
                selectedNavItem = .attendance
            }
            self.appRouter.clearNavigation()
        }

        #if os(macOS)
        if case .openStudentDetail(let studentID) = destination {
            openWindow(id: "StudentDetailWindow", value: studentID)
            self.appRouter.clearNavigation()
        }
        #endif
    }

    private func handleSelectedNavItemChange(_ oldValue: RootView.NavigationItem?, _ item: RootView.NavigationItem?) {
        if let item {
            if selectedNavItem != item {
                selectedNavItem = item
            }
            self.appRouter.selectedNavItem = nil
        }
    }

}

#Preview {
    let dependencies = AppDependencies(coreDataStack: CoreDataStack.preview)
    let workspace = ClassroomWorkspaceStore(
        primaryStack: CoreDataStack.preview,
        primaryDependencies: dependencies
    )
    RootView(classroomWorkspace: workspace)
        .environment(\.dependencies, dependencies)
        .previewEnvironment(using: CoreDataStack.preview)
}
