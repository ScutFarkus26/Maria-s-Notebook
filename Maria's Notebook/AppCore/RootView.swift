// RootView.swift
// App root container with top pill navigation and tab routing.
//
// Split into multiple files for maintainability:
// - RootView.swift (this file) - Main view structure and body
// - RootSidebar.swift - Sidebar navigation component
// - RootDetailContent.swift - Detail content routing
// - RootViewComponents.swift - Supporting components (QuickNoteGlassButton, warning banners)

import SwiftUI
import SwiftData
import OSLog
import TipKit

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
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @Environment(\.dependencies) private var dependencies
    @Environment(\.calendar) private var calendar
    private let quickNoteTip = QuickNoteTip()
    @State private var isShowingQuickNote = false
    @State private var isShowingCommandBar = false
    @State private var newPresentationDraftID: UUID?
    @State private var isShowingNewWorkItem = false
    @State private var isShowingRecordPractice = false
    @State private var isShowingNewTodo = false
    @State private var workDetailIDToOpen: UUID?

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
    private var selectedNavItem: NavigationItem {
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
        .onAppear(perform: handleMigration)
        .onChange(of: appRouter.navigationDestination, handleNavigationDestinationChange)
        .onChange(of: appRouter.selectedNavItem, handleSelectedNavItemChange)
        .onChange(of: appRouter.selectedTab, handleSelectedTabChange)
        .saveErrorAlert()
        .toastOverlay(ToastService.shared)
        .overlay(alignment: .bottom) {
            TipView(quickNoteTip, arrowEdge: .bottom)
                .padding(.horizontal, 24)
                .padding(.bottom, 80)
        }
        .overlay(alignment: .bottomTrailing) {
            QuickNoteGlassButton(
                isShowingCommandBar: $isShowingCommandBar,
                onNewPresentation: {
                    let draft = PresentationFactory.makeDraft(lessonID: UUID(), studentIDs: [])
                    modelContext.insert(draft)
                    do {
                        try modelContext.save()
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
                    #if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
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
        RootAdaptiveTabs(selectedNavItem: Binding(
            get: { selectedNavItem },
            set: { selectedNavItemRaw = $0.rawValue }
        ))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        splitViewContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

    private var splitViewContent: some View {
        NavigationSplitView {
            RootSidebar(selection: Binding(
                get: { selectedNavItem },
                set: { selectedNavItemRaw = $0.rawValue }
            ))
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            RootDetailContent(selectedNavItem: selectedNavItem)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .navigationDestination(for: RootView.NavigationItem.self) { item in
                    RootDetailContent(selectedNavItem: item)
                }
        }
    }

    // MARK: - Event Handlers

    // swiftlint:disable:next cyclomatic_complexity
    private func handleMigration() {
        guard self.selectedNavItemRaw == nil, let legacyRaw = self.selectedTabRaw else { return }

        var targetItem: RootView.NavigationItem?

        if legacyRaw == "Lesson Planning" {
            targetItem = .planningAgenda
        } else if legacyRaw == "Work Planning" || legacyRaw == "Work" {
            targetItem = .planningWork
        } else if let legacyTab = RootView.Tab(rawValue: legacyRaw) {
            if let navItem = RootView.NavigationItem(fromLegacyTab: legacyTab) {
                if legacyTab == .planning {
                    if let modeRaw = UserDefaults.standard.string(forKey: UserDefaultsKeys.planningRootViewMode) {
                        switch modeRaw {
                        case "Open Work": targetItem = .planningWork
                        case "Projects": targetItem = .planningProjects
                        case "Checklist": targetItem = .planningChecklist
                        default: targetItem = .planningAgenda
                        }
                    } else {
                        targetItem = .planningAgenda
                    }
                } else {
                    targetItem = navItem
                }
            }
        }

        if let target = targetItem {
            self.selectedNavItemRaw = target.rawValue
        }
    }

    private func handleNavigationDestinationChange(
        _ oldValue: AppRouter.NavigationDestination?,
        _ destination: AppRouter.NavigationDestination?
    ) {
        if case .openAttendance = destination {
            let newValue = RootView.NavigationItem.attendance.rawValue
            if self.selectedNavItemRaw != newValue {
                self.selectedNavItemRaw = newValue
            }
            self.appRouter.clearNavigation()
        }
    }

    private func handleSelectedNavItemChange(_ oldValue: RootView.NavigationItem?, _ item: RootView.NavigationItem?) {
        if let item {
            let newValue = item.rawValue
            if self.selectedNavItemRaw != newValue {
                self.selectedNavItemRaw = newValue
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
        if self.selectedNavItemRaw != newValue {
            self.selectedNavItemRaw = newValue
        }
        self.appRouter.selectedTab = nil
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}
