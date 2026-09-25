// RootView.swift
// App root container with top pill navigation and tab routing.
//
// Split into multiple files for maintainability:
// - RootView.swift (this file) - Main view structure and body
// - RootView+NavigationItem.swift - NavigationItem, legacy Tab, selection restore
// - RootView+NavigationGroup.swift - The sidebar / tab grouping table
// - RootView/RootSidebar.swift - macOS / visionOS sidebar
// - RootView/RootAdaptiveTabs.swift - iPhone tab bar / iPad sidebar
// - RootView/RootDetailContent.swift - Detail content routing
// - RootView/QuickNoteGlassButton.swift, WarningBanners.swift - Overlays

import Combine
import SwiftUI
import CoreData
import OSLog
#if !os(macOS)
import TipKit
#endif

// Top-level container that manages app-wide navigation between Students, Albums, Planning, Today, Logs, and Settings.
// NavigationItem and Tab enums live in RootView+NavigationItem.swift.
// swiftlint:disable:next type_body_length
struct RootView: View {
    static let logger = Logger.app_
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
    @State var activeSheet: ActiveSheet?
    @State private var focusedSearchAction = FocusedSearchAction()
    @State private var quickCaptureActions = QuickCaptureActions()
    @State private var selectedNavItem: NavigationItem = .today
    @State private var companionViewModel = NotebookCompanionViewModel()
    @AppStorage(UserDefaultsKeys.notebookCompanionVisible)
    private var isNotebookCompanionVisible = true
    @AppStorage(UserDefaultsKeys.notebookCompanionDetached)
    private var isNotebookCompanionDetached = false

    // Preferences for presentations preloading
    
    // MARK: - Computed
    /// The saved selection, migrated by `NavigationSelectionRestorer` (retired
    /// raw values, the legacy `Tab` enum, aliased cases). A restore that lands
    /// on the Lessons & Work workspace also carries which lens to open.
    private func resolvedPersistedNavItem() -> NavigationItem {
        let resolution = NavigationSelectionRestorer.resolve(
            navItemRaw: selectedNavItemRaw,
            legacyTabRaw: selectedTabRaw,
            planningModeRaw: UserDefaults.standard.string(forKey: UserDefaultsKeys.planningRootViewMode)
        )
        if let scope = resolution.lessonsAndWorkScope {
            appRouter.lessonsAndWorkRequest = .init(scope: scope)
        }
        return resolution.item
    }

    // MARK: - Body
    var body: some View {
        rootWithQuickActions
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        // Expose key-window actions to the menu bar (Find…, File > New quick-capture).
        // Only the key main window's RootView provides these, so menu commands act
        // on exactly one window and disable when no main window is frontmost.
        .focusedSceneValue(\.openSearch, focusedSearchAction)
        .onAppear {
            focusedSearchAction.setAction {
                activeSheet = .search
            }
            installQuickCaptureHandlers()
        }
        .onDisappear {
            focusedSearchAction.clearAction()
        }
        // One object for the window's life, so File > New is not rebuilt on
        // every RootView body pass; the handlers are refilled only when the
        // context or dependencies they capture change.
        .focusedSceneValue(\.quickCapture, quickCaptureActions)
        .onChange(of: quickCaptureInputs) {
            installQuickCaptureHandlers()
        }
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
                    isShowingCommandBar: isPresenting(.commandBar),
                    onNewPresentation: { createPresentationDraft() },
                    isShowingWorkItemSheet: isPresenting(.newWorkItem(lessonID: nil, studentIDs: [])),
                    onRecordPractice: {
                        activeSheet = .recordPractice
                    },
                    onNewTodo: {
                        activeSheet = .newTodo(initialTitle: "")
                    },
                    onNewNote: {
                        activeSheet = .quickNote(QuickNoteParams())
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
                    .background(
                        .regularMaterial,
                        in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                    )
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

    /// Whether the in-window companion (the glass button) is on screen; it
    /// is the only reader of `companionViewModel.snapshot`.
    private var showsInWindowCompanion: Bool {
        isNotebookCompanionVisible && !isNotebookCompanionDetached
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
            // The in-window counts only refresh while shown (below), so catch
            // up the moment they are shown again.
            if showsInWindowCompanion { companionViewModel.reload(calendar: calendar) }
            #if os(macOS)
            if isVisible && isNotebookCompanionDetached {
                openWindow(id: "notebookCompanion")
            } else if !isVisible {
                dismissWindow(id: "notebookCompanion")
            }
            #endif
        }
        .onChange(of: isNotebookCompanionDetached) { _, _ in
            if showsInWindowCompanion { companionViewModel.reload(calendar: calendar) }
        }
        // Debounce: objectsDidChange fires per change, not per save, so a single
        // CloudKit merge can post it hundreds of times — and each reload runs the
        // companion's count queries. Coalesce them (same pattern as StudentsView).
        // Only changes to the counted entities matter, and only while the
        // in-window companion is on screen: hidden, nothing reads the counts,
        // and detached, its own window keeps its own.
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange,
                object: viewContext
            )
            .filter(NotebookCompanionViewModel.affectsCounts)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
        ) { _ in
            guard showsInWindowCompanion else { return }
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
            activeSheet = .newWorkItem(lessonID: nil, studentIDs: [])
        }
        .onChange(of: appRouter.triggerRecordPractice) { _, value in
            guard value else { return }
            appRouter.triggerRecordPractice = false
            activeSheet = .recordPractice
        }
        .onChange(of: appRouter.triggerNewPresentation) { _, value in
            guard value else { return }
            appRouter.triggerNewPresentation = false
            createPresentationDraft()
        }
        .onChange(of: appRouter.triggerCommandBar) { _, value in
            guard value else { return }
            appRouter.triggerCommandBar = false
            activeSheet = .commandBar
        }
    }

    /// What the quick-capture handlers capture by copy.
    private var quickCaptureInputs: [ObjectIdentifier] {
        [ObjectIdentifier(viewContext), ObjectIdentifier(dependencies)]
    }

    /// File > New's quick-capture actions — the radial menu's set.
    private func installQuickCaptureHandlers() {
        quickCaptureActions.setHandlers(QuickCaptureActions.Handlers(
            newPresentation: { createPresentationDraft() },
            recordPractice: { activeSheet = .recordPractice },
            newTodo: { activeSheet = .newTodo(initialTitle: "") },
            newNote: { activeSheet = .quickNote(QuickNoteParams()) }
        ))
    }

    /// Creates a presentation draft and opens its editor sheet. Shared by the
    /// iOS toolbar trigger, the radial quick-command menu, and File > New.
    private func createPresentationDraft() {
        let draft = PresentationFactory.makeDraft(lessonID: UUID(), studentIDs: [], context: viewContext)
        dependencies.saveCoordinator.save(viewContext, reason: "Create presentation draft")
        if let draftID = draft.id {
            activeSheet = .presentationDraft(draftID)
        }
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
                activeSheet = .search
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
                activeSheet = .search
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
                activeSheet = .search
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
            let destination = item.canonical
            if selectedNavItem != destination {
                selectedNavItem = destination
            }
            self.appRouter.selectedNavItem = nil
        }
    }

}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct RootViewPreview: View {
    var body: some View {
        let dependencies = AppDependencies(coreDataStack: CoreDataStack.preview)
        let workspace = ClassroomWorkspaceStore(
            primaryStack: CoreDataStack.preview,
            primaryDependencies: dependencies
        )
        RootView(classroomWorkspace: workspace)
            .environment(\.dependencies, dependencies)
            .previewEnvironment(using: CoreDataStack.preview)
    }
}

#Preview {
    RootViewPreview()
}
