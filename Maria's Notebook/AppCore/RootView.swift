// RootView.swift
// App root container with top pill navigation and tab routing.
//
// Split into multiple files for maintainability:
// - RootView.swift (this file) - Main view structure and body
// - RootSidebar.swift - Sidebar navigation component
// - RootDetailContent.swift - Detail content routing
// - RootViewComponents.swift - Supporting components (QuickNoteGlassButton, warning banners)

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

    // MARK: - Storage
    @SceneStorage("RootView.selectedNavItem") private var selectedNavItemRaw: String?
    @SceneStorage("RootView.selectedTab") private var selectedTabRaw: String?
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.dependencies) private var dependencies
    @Environment(\.calendar) private var calendar
    #if !os(macOS)
    private let quickNoteTip = QuickNoteTip()
    #endif
    @State private var isShowingQuickNote = false
    @State private var isShowingCommandBar = false
    @State private var isShowingSearch = false
    @State private var newPresentationDraftID: UUID?
    @State private var isShowingNewWorkItem = false
    @State private var isShowingRecordPractice = false
    @State private var isShowingNewTodo = false
    @State private var workDetailIDToOpen: UUID?
    @State private var selectedNavItem: NavigationItem = .today

    // Command bar pre-population state
    @State private var commandBarNoteStudentID: UUID?
    @State private var commandBarNoteText: String = ""
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
    private func resolvedPersistedNavItem() -> NavigationItem {
        if let raw = selectedNavItemRaw, let item = NavigationItem(rawValue: raw) {
            return item
        }
        if let legacyRaw = selectedTabRaw, let legacyTab = Tab(rawValue: legacyRaw) {
            if legacyTab == .planning {
                if let modeRaw = UserDefaults.standard.string(forKey: UserDefaultsKeys.planningRootViewMode) {
                    switch modeRaw {
                    case "Open Work": return .planningWork
                    case "Projects": return .planningProjects
                    case "Checklist": return .planningChecklist
                    default: return .planningAgenda
                    }
                }
                return .planningAgenda
            }
            if let item = NavigationItem(fromLegacyTab: legacyTab) {
                return item
            }
        }
        return .today
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            warningBanners
            Divider()
            mainContent
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                Button {
                    isShowingSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Search")
                CompactSyncStatusIndicator(compact: true)
            }
            .padding(.trailing, 12)
            .padding(.top, 6)
        }
        .onAppear(perform: restoreSelectionIfNeeded)
        .onChange(of: selectedNavItem) { _, item in
            persistSelection(item)
        }
        .onChange(of: appRouter.navigationDestination, handleNavigationDestinationChange)
        .onChange(of: appRouter.selectedNavItem, handleSelectedNavItemChange)
        .onChange(of: appRouter.selectedTab, handleSelectedTabChange)
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
            QuickNoteGlassButton(
                isShowingCommandBar: $isShowingCommandBar,
                onNewPresentation: {
                    let draft = PresentationFactory.makeDraft(lessonID: UUID(), studentIDs: [], context: viewContext)
                    do {
                        try viewContext.save()
                    } catch {
                        Self.logger.error("Failed to save new presentation draft: \(error)")
                    }
                    newPresentationDraftID = draft.id
                },
                isShowingWorkItemSheet: $isShowingNewWorkItem,
                onRecordPractice: {
                    isShowingRecordPractice = true
                },
                onNewTodo: {
                    isShowingNewTodo = true
                },
                onNewNote: {
                    isShowingQuickNote = true
                }
            )
        }
        .sheet(isPresented: $isShowingQuickNote) {
            QuickNoteSheet(
                initialStudentID: commandBarNoteStudentID,
                initialBodyText: commandBarNoteText
            )
            .onDisappear {
                commandBarNoteStudentID = nil
                commandBarNoteText = ""
            }
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
                onNote: { studentID, bodyText in
                    isShowingCommandBar = false
                    commandBarNoteStudentID = studentID
                    commandBarNoteText = bodyText
                    isShowingQuickNote = true
                },
                onTodo: { titleText in
                    isShowingCommandBar = false
                    commandBarTodoTitle = titleText
                    isShowingNewTodo = true
                }
            )
        }
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

    @ViewBuilder
    private var warningBanners: some View {
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag) {
            EphemeralStoreWarningBanner()
        }

        let cloudStatus = CloudKitConfiguration.getCloudKitStatus()
        if cloudStatus.enabled && !cloudStatus.active {
            CloudKitSyncWarningBanner()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        #if os(iOS)
        RootAdaptiveTabs(selectedNavItem: $selectedNavItem)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        splitViewContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private var splitViewContent: some View {
        NavigationSplitView {
            RootSidebar(selection: $selectedNavItem)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            RootDetailContent(selectedNavItem: selectedNavItem)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Event Handlers

    // swiftlint:disable:next cyclomatic_complexity
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
    }

    private func handleSelectedNavItemChange(_ oldValue: RootView.NavigationItem?, _ item: RootView.NavigationItem?) {
        if let item {
            if selectedNavItem != item {
                selectedNavItem = item
            }
            self.appRouter.selectedNavItem = nil
        }
    }

    private func handleSelectedTabChange(_ oldValue: RootView.Tab?, _ tab: RootView.Tab?) {
        guard let tab, let navItem = RootView.NavigationItem(fromLegacyTab: tab) else { return }
        let newValue: String
        if tab == .planning {
            newValue = RootView.NavigationItem.planningAgenda.rawValue
        } else {
            newValue = navItem.rawValue
        }
        if let item = RootView.NavigationItem(rawValue: newValue), selectedNavItem != item {
            selectedNavItem = item
        }
        self.appRouter.selectedTab = nil
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
