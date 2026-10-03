// RootView.swift
// App root container with top pill navigation and tab routing.
//
// Split into multiple files for maintainability:
// - RootView.swift (this file) - Main view structure and body
// - RootView+NavigationItem.swift - NavigationItem, legacy Tab, selection restore
// - RootView+NavigationGroup.swift - The sidebar / tab grouping table
// - RootView+Chrome.swift - Phone context bar, search / sync overlay, warning banners
// - RootView/RootSidebar.swift - macOS / visionOS sidebar
// - RootView/RootAdaptiveTabs.swift - iPhone tab bar / iPad sidebar
// - RootView/RootDetailContent.swift - Detail content routing
// - RootView/QuickNoteGlassButton.swift, WarningBanners.swift - Overlays

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
    @Environment(\.dependencies) var dependencies
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private let quickNoteTip = QuickNoteTip()
    #endif
    @State var activeSheet: ActiveSheet?
    @State private var focusedSearchAction = FocusedSearchAction()
    @State private var quickCaptureActions = QuickCaptureActions()
    @State var selectedNavItem: NavigationItem = .today
    @AppStorage(UserDefaultsKeys.quickCaptureButtonVisible)
    private var isQuickCaptureButtonVisible = true

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
            // Not over Attendance, where it sat on Insights and the tiles.
            if isQuickCaptureButtonVisible, selectedNavItem != .attendance {
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
            Text(classroomWorkspace.preparationErrorMessage ?? ClassroomWorkspaceStore.samplePreparationFailedMessage)
        }
        .alert(
            "The \(dependencies.schoolYearStore.current.label) School Year Has Begun",
            isPresented: Binding(
                get: { dependencies.schoolYearStore.needsNewYearPrompt },
                set: { isPresented in
                    if !isPresented { dependencies.schoolYearStore.keepCurrentView() }
                }
            )
        ) {
            Button("View \(dependencies.schoolYearStore.current.label)") {
                dependencies.schoolYearStore.switchToNewYear()
            }
            Button("Not Now", role: .cancel) { dependencies.schoolYearStore.keepCurrentView() }
        } message: {
            Text(schoolYearPromptMessage)
        }
    }

    /// Says what switching does: the lens only. Day counters already follow the new year on
    /// their own, and nothing is moved or deleted.
    private var schoolYearPromptMessage: String {
        let store = dependencies.schoolYearStore
        let start = store.current.start.formatted(.dateTime.month(.wide).day().year())
        let counters = store.isResettingCounters
            ? " Day counters already start over on \(start)."
            : ""
        return "Show \(store.current.label) across the notebook?\(counters) "
            + "Last year's records stay exactly as they are."
    }

    private var rootLayoutWithObservers: some View {
        rootLayout
        .onAppear(perform: restoreSelectionIfNeeded)
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
            newWork: { activeSheet = .newWorkItem(lessonID: nil, studentIDs: []) },
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
            if usesPhoneChrome {
                mobileContextBar
            }
            Divider()
            mainContent
        }

        if usesPhoneChrome {
            layout
        } else {
            layout
                .overlay(alignment: .topTrailing) {
                    searchAndSyncOverlay
                }
        }
        #endif
    }

    #if !os(macOS)
    /// The iPhone's context bar instead of the corner overlay: on iPhone, and on
    /// the iPad mini, which also takes the iPhone's bottom tab bar.
    private var usesPhoneChrome: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact || RootAdaptiveTabs.usesBottomTabBar
        #else
        horizontalSizeClass == .compact
        #endif
    }
    #endif

    /// On iPhone the context bar shows Sample Class itself, so the full-width
    /// banner is left out there.
    var showsSampleStateInContextBar: Bool {
        #if os(iOS)
        usesPhoneChrome
        #else
        false
        #endif
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

        // Hidden on Today, never removed: an `if` here would change the item
        // list, which AppKit replays across toolbars sharing the identifier
        // (the album window's family-desync crash). See SyncStatusToolbarItem.
        ToolbarItem(id: "schoolYear", placement: .primaryAction) {
            SchoolYearPicker()
        }
        .hidden(selectedNavItem == .today)

        ToolbarItem(id: "search", placement: .primaryAction) {
            Button {
                activeSheet = .search
            } label: {
                Label("Search", systemImage: "magnifyingglass")
            }
            .help("Search notes, lessons, students, and todos (⌘F)")
        }

        SyncStatusToolbarItem(isSampleClass: classroomWorkspace.isShowingSampleClass)
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
