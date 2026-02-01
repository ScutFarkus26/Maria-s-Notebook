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

extension UUID: @retroactive Identifiable {
    public var id: UUID { self }
}

/// Top-level container that manages app-wide navigation between Students, Albums, Planning, Today, Logs, and Settings.
struct RootView: View {
    // MARK: - Navigation Items
    enum NavigationItem: String, Hashable, Identifiable {
        case today
        case attendance
        case note
        case students
        case supplies
        case procedures
        case meetings
        case lessons
        case more

        // Planning Sub-items
        case planningChecklist
        case planningAgenda
        case planningWork
        case planningProjects

        case community
        case logs
        case settings

        var id: Self { self }

        var displayName: String {
            switch self {
            case .today: return "Today"
            case .attendance: return "Attendance"
            case .note: return "Note"
            case .students: return "Students"
            case .supplies: return "Supplies"
            case .procedures: return "Procedures"
            case .meetings: return "Meetings"
            case .lessons: return "Lessons"
            case .more: return "More"
            case .planningChecklist: return "Checklist"
            case .planningAgenda: return "Presentations"
            case .planningWork: return "Open Work"
            case .planningProjects: return "Projects"
            case .community: return "Community"
            case .logs: return "Logs"
            case .settings: return "Settings"
            }
        }

        var icon: String {
            switch self {
            case .today: return "sun.max"
            case .attendance: return "checklist"
            case .note: return "square.and.pencil"
            case .students: return "person.3"
            case .supplies: return "shippingbox"
            case .procedures: return "doc.text"
            case .meetings: return "person.2"
            case .lessons: return "book"
            case .more: return "ellipsis.circle"
            case .planningChecklist: return "list.clipboard"
            case .planningAgenda: return "calendar"
            case .planningWork: return "tray.full"
            case .planningProjects: return "folder"
            case .community: return "bubble.left.and.bubble.right"
            case .logs: return "list.bullet"
            case .settings: return "gear"
            }
        }

        init?(fromLegacyTab tab: Tab) {
            switch tab {
            case .today: self = .today
            case .attendance: self = .attendance
            case .students: self = .students
            case .albums: self = .lessons
            case .planning: self = .planningAgenda
            case .community: self = .community
            case .logs: self = .logs
            case .settings: self = .settings
            }
        }

        var isInMoreMenu: Bool {
            switch self {
            case .lessons, .supplies, .procedures, .meetings, .planningChecklist, .planningAgenda, .planningWork, .planningProjects, .community, .logs, .settings:
                return true
            default:
                return false
            }
        }

        var legacyTab: Tab? {
            switch self {
            case .today: return .today
            case .attendance: return .attendance
            case .note: return nil
            case .students: return .students
            case .supplies: return nil
            case .procedures: return nil
            case .meetings: return nil
            case .lessons: return .albums
            case .more: return nil
            case .planningChecklist, .planningAgenda, .planningWork, .planningProjects: return .planning
            case .community: return .community
            case .logs: return .logs
            case .settings: return .settings
            }
        }
    }

    // MARK: - Legacy Tabs (kept for backward compatibility)
    enum Tab: String, CaseIterable, Identifiable {
        case students = "Students"
        case albums = "Lessons"
        case planning = "Planning"
        case today = "Today"
        case logs = "Logs"
        case attendance = "Attendance"
        case community = "Community"
        case settings = "Settings"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .students: return "person.3"
            case .albums: return "book"
            case .planning: return "calendar"
            case .today: return "sun.max"
            case .logs: return "list.bullet"
            case .attendance: return "checklist"
            case .community: return "bubble.left.and.bubble.right"
            case .settings: return "gear"
            }
        }
    }

    // MARK: - Storage
    @SceneStorage("RootView.selectedNavItem") private var selectedNavItemRaw: String?
    @SceneStorage("RootView.selectedTab") private var selectedTabRaw: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @State private var isShowingQuickNote = false
    @State private var isShowingNewPresentation = false
    @State private var isShowingNewWorkItem = false
    @State private var workDetailIDToOpen: UUID?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

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
        .overlay(alignment: .bottomTrailing) {
            QuickNoteGlassButton(
                isShowingSheet: $isShowingQuickNote,
                isShowingPresentationSheet: $isShowingNewPresentation,
                isShowingWorkItemSheet: $isShowingNewWorkItem
            )
        }
        .sheet(isPresented: $isShowingQuickNote) {
            QuickNoteSheet()
        }
        .sheet(isPresented: $isShowingNewPresentation) {
            QuickNewPresentationSheet()
        }
        .sheet(isPresented: $isShowingNewWorkItem) {
            QuickNewWorkItemSheet { workID in
                // Delay slightly to allow sheet dismiss animation to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    workDetailIDToOpen = workID
                }
            }
        }
        .sheet(item: $workDetailIDToOpen) { workID in
            WorkDetailView(workID: workID, onDone: { workDetailIDToOpen = nil })
            #if os(macOS)
                .frame(minWidth: 720, minHeight: 640)
                .presentationSizingFitted()
            #else
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            #endif
        }
    #if os(macOS)
        .background(EnsureResizableWindow(minSize: NSSize(width: 900, height: 600)))
    #endif
    }

    // MARK: - View Components

    @ViewBuilder
    private var warningBanners: some View {
        if UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag) {
            EphemeralStoreWarningBanner()
        }

        let cloudStatus = MariasNotebookApp.getCloudKitStatus()
        if cloudStatus.enabled && !cloudStatus.active {
            CloudKitSyncWarningBanner()
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        #if os(iOS)
        Group {
            if horizontalSizeClass == .compact {
                RootCompactTabs(selectedNavItem: Binding(
                    get: { selectedNavItem },
                    set: { selectedNavItemRaw = $0.rawValue }
                ))
            } else {
                splitViewContent
            }
        }
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

    private func handleMigration() {
        DispatchQueue.main.async {
            guard self.selectedNavItemRaw == nil, let legacyRaw = self.selectedTabRaw else { return }

            var targetItem: RootView.NavigationItem? = nil

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
    }

    private func handleNavigationDestinationChange(_ oldValue: AppRouter.NavigationDestination?, _ destination: AppRouter.NavigationDestination?) {
        DispatchQueue.main.async {
            if case .openAttendance = destination {
                let newValue = RootView.NavigationItem.attendance.rawValue
                if self.selectedNavItemRaw != newValue {
                    self.selectedNavItemRaw = newValue
                }
                self.appRouter.clearNavigation()
            }
        }
    }

    private func handleSelectedNavItemChange(_ oldValue: RootView.NavigationItem?, _ item: RootView.NavigationItem?) {
        DispatchQueue.main.async {
            if let item = item {
                let newValue = item.rawValue
                if self.selectedNavItemRaw != newValue {
                    self.selectedNavItemRaw = newValue
                }
                self.appRouter.selectedNavItem = nil
            }
        }
    }

    private func handleSelectedTabChange(_ oldValue: RootView.Tab?, _ tab: RootView.Tab?) {
        DispatchQueue.main.async {
            guard let tab = tab, let navItem = RootView.NavigationItem(fromLegacyTab: tab) else { return }
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
}

#Preview {
    RootView()
        .previewEnvironment()
}
