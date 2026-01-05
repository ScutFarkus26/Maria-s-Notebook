// RootView.swift
// App root container with top pill navigation and tab routing.
// Behavior-preserving cleanup: comments and MARKs only.

import SwiftUI
import SwiftData
import Combine

/// Top-level container that manages app-wide navigation between Students, Albums, Planning, Today, Logs, and Settings.
struct RootView: View {
    // MARK: - Navigation Items
    enum NavigationItem: String, Hashable, Identifiable {
        case today
        case attendance
        case note
        case students
        case lessons // Previously "Albums"
        case more
        
        // Planning Sub-items (Promoted from PlanningRootView pills)
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
        
        // Helper to convert from legacy Tab enum for migration
        init?(fromLegacyTab tab: Tab) {
            switch tab {
            case .today: self = .today
            case .attendance: self = .attendance
            case .students: self = .students
            case .albums: self = .lessons
            case .planning: self = .planningAgenda // Default to agenda for planning
            case .community: self = .community
            case .logs: self = .logs
            case .settings: self = .settings
            }
        }
        
        // Check if this item should be in the More menu on iPhone
        var isInMoreMenu: Bool {
            switch self {
            case .lessons, .planningChecklist, .planningAgenda, .planningWork, .planningProjects, .community, .logs, .settings:
                return true
            default:
                return false
            }
        }
        
        // Helper to convert legacy Tab for backward compatibility
        var legacyTab: Tab? {
            switch self {
            case .today: return .today
            case .attendance: return .attendance
            case .note: return nil // Note is a new feature, no legacy tab
            case .students: return .students
            case .lessons: return .albums
            case .more: return nil // More is a new feature, no legacy tab
            case .planningChecklist, .planningAgenda, .planningWork, .planningProjects: return .planning
            case .community: return .community
            case .logs: return .logs
            case .settings: return .settings
            }
        }
    }
    
    // MARK: - Legacy Tabs (kept for backward compatibility and migration)
    enum Tab: String, CaseIterable, Identifiable {
        case students = "Students"
        case albums = "Lessons" // Renamed from "Albums" to "Lessons"
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
    // Legacy storage for migration
    @SceneStorage("RootView.selectedTab") private var selectedTabRaw: String?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @State private var isShowingQuickNote = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    // MARK: - Computed
    private var selectedNavItem: NavigationItem {
        // First, try to use the new navigation item
        if let raw = selectedNavItemRaw, let item = NavigationItem(rawValue: raw) {
            return item
        }
        // Migration: try to read from legacy selectedTab
        if let legacyRaw = selectedTabRaw, let legacyTab = Tab(rawValue: legacyRaw) {
            // Special handling for planning tab: check stored mode first
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
            // For non-planning tabs, convert using the initializer
            if let item = NavigationItem(fromLegacyTab: legacyTab) {
                return item
            }
        }
        // Default fallback
        return .today
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            if UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag) {
                EphemeralStoreWarningBanner()
            }
            
            let cloudStatus = MariasToolboxApp.getCloudKitStatus()
            if cloudStatus.enabled && !cloudStatus.active {
                CloudKitSyncWarningBanner()
            }

            Divider()

            #if os(iOS)
            Group {
                if horizontalSizeClass == .compact {
                    RootCompactTabs(selectedNavItem: Binding(
                        get: { selectedNavItem },
                        set: { selectedNavItemRaw = $0.rawValue }
                    ))
                } else {
                    NavigationSplitView {
                        RootSidebar(selection: Binding(
                            get: { selectedNavItem },
                            set: { selectedNavItemRaw = $0.rawValue }
                        ))
                    } detail: {
                        RootDetailContent(selectedNavItem: selectedNavItem)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .navigationDestination(for: RootView.NavigationItem.self) { item in
                                RootDetailContent(selectedNavItem: item)
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            NavigationSplitView {
                RootSidebar(selection: Binding(
                    get: { selectedNavItem },
                    set: { selectedNavItemRaw = $0.rawValue }
                ))
            } detail: {
                RootDetailContent(selectedNavItem: selectedNavItem)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationDestination(for: RootView.NavigationItem.self) { item in
                        RootDetailContent(selectedNavItem: item)
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
        .onAppear {
            // Migration: Convert legacy selectedTab to selectedNavItem if needed
            if selectedNavItemRaw == nil, let legacyRaw = selectedTabRaw {
                if let legacyTab = Tab(rawValue: legacyRaw) {
                    if let navItem = NavigationItem(fromLegacyTab: legacyTab) {
                        // For planning, check stored mode
                        if legacyTab == .planning {
                            if let modeRaw = UserDefaults.standard.string(forKey: UserDefaultsKeys.planningRootViewMode) {
                                switch modeRaw {
                                case "Open Work": selectedNavItemRaw = NavigationItem.planningWork.rawValue
                                case "Projects": selectedNavItemRaw = NavigationItem.planningProjects.rawValue
                                case "Checklist": selectedNavItemRaw = NavigationItem.planningChecklist.rawValue
                                default: selectedNavItemRaw = NavigationItem.planningAgenda.rawValue
                                }
                            } else {
                                selectedNavItemRaw = NavigationItem.planningAgenda.rawValue
                            }
                        } else {
                            selectedNavItemRaw = navItem.rawValue
                        }
                    }
                }
                // Handle legacy string migrations
                if legacyRaw == "Lesson Planning" {
                    selectedNavItemRaw = NavigationItem.planningAgenda.rawValue
                }
                if legacyRaw == "Work Planning" || legacyRaw == "Work" {
                    selectedNavItemRaw = NavigationItem.planningWork.rawValue
                }
            }
        }
        .onChange(of: appRouter.navigationDestination) { _, destination in
            if case .openAttendance = destination {
                selectedNavItemRaw = NavigationItem.attendance.rawValue
                appRouter.clearNavigation()
            }
        }
        .onChange(of: appRouter.selectedNavItem) { _, item in
            if let item = item {
                selectedNavItemRaw = item.rawValue
                appRouter.selectedNavItem = nil // Clear after handling
            }
        }
        // Backward compatibility: handle legacy selectedTab
        .onChange(of: appRouter.selectedTab) { _, tab in
            if let tab = tab, let navItem = NavigationItem(fromLegacyTab: tab) {
                // For planning, default to agenda
                if tab == .planning {
                    selectedNavItemRaw = NavigationItem.planningAgenda.rawValue
                } else {
                    selectedNavItemRaw = navItem.rawValue
                }
                appRouter.selectedTab = nil // Clear after handling
            }
        }
        .saveErrorAlert()
        .overlay(alignment: .bottomTrailing) {
            QuickNoteGlassButton(isShowingSheet: $isShowingQuickNote)
        }
        .sheet(isPresented: $isShowingQuickNote) {
            QuickNoteSheet()
        }
    #if os(macOS)
        .background(EnsureResizableWindow(minSize: NSSize(width: 900, height: 600)))
    #endif
    }
}

// MARK: - Quick Note Glass Button

/// Isolated component to prevent RootView re-renders during drag
struct QuickNoteGlassButton: View {
    @Binding var isShowingSheet: Bool
    
    @State private var offset: CGSize = .zero
    @State private var isPressed: Bool = false // For that native "squish" feel
    
    @AppStorage("QuickNoteButton.offsetX") private var savedOffsetX: Double = 0
    @AppStorage("QuickNoteButton.offsetY") private var savedOffsetY: Double = 0
    
    var body: some View {
        // 1. Define the visual look (No Button wrapper, we handle gestures manually)
        let visualContent = Group {
            #if os(iOS)
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            #else
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
            #endif
        }

        return visualContent
            .scaleEffect(isPressed ? 0.92 : 1.0) // Native "Breathe" animation on touch
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .offset(offset)
            .padding(.trailing, 20)
            #if os(iOS)
            .padding(.bottom, 85) // Positioned just above tab bar, inspired by Things' magic button
            #else
            .padding(.bottom, 40)
            #endif
            // 2. The "Native" Gesture Logic
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isPressed = true
                        
                        // Immediate 1:1 tracking (Direct Manipulation)
                        self.offset = CGSize(
                            width: savedOffsetX + value.translation.width,
                            height: savedOffsetY + value.translation.height
                        )
                    }
                    .onEnded { value in
                        isPressed = false
                        
                        // 3. Distinguish Tap vs. Drag
                        // If moved less than 2 points, it's a Tap.
                        let distance = hypot(value.translation.width, value.translation.height)
                        
                        if distance < 2 {
                            // TAP ACTION: Reset drift and Open
                            self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
                            isShowingSheet = true
                        } else {
                            // DRAG ACTION: Save new position
                            let finalOffset = CGSize(
                                width: savedOffsetX + value.translation.width,
                                height: savedOffsetY + value.translation.height
                            )
                            savedOffsetX = finalOffset.width
                            savedOffsetY = finalOffset.height
                            
                            // Native snapping animation (no bounce/wobble)
                            withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                                self.offset = finalOffset
                            }
                        }
                    }
            )
            .onAppear {
                self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
            }
    }
}

/// Extracted detail content for RootView. Routes based on NavigationItem selection.
private struct RootDetailContent: View {
    let selectedNavItem: RootView.NavigationItem
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appRouter) private var appRouter
    @State private var isShowingQuickNote = false

    var body: some View {
        Group {
            switch selectedNavItem {
            case .today:
                TodayView(context: modelContext)
            case .attendance:
                AttendanceView()
            case .note:
                // Note tab opens QuickNoteSheet immediately when selected
                Color.clear
                    .onAppear {
                        // Always show the sheet when note tab is selected
                        isShowingQuickNote = true
                    }
                    .sheet(isPresented: $isShowingQuickNote) {
                        QuickNoteSheet()
                            .onDisappear {
                                // Navigate to Today tab after sheet is dismissed
                                appRouter.navigateTo(.today)
                            }
                    }
            case .students:
                StudentsRootView()
            case .more:
                MoreMenuView()
            case .lessons:
                LessonsMenuRootView()
            case .planningChecklist:
                ClassSubjectChecklistView()
            case .planningAgenda:
                PresentationsView()
            case .planningWork:
                WorksAgendaView()
            case .planningProjects:
                // FIX: Removed NavigationStack wrapper to avoid nested stacks in More menu (iPhone)
                // ProjectsRootView now handles its own split view layout
                ProjectsRootView()
            case .community:
                CommunityMeetingsView()
            case .logs:
                LogsMenuRootView()
            case .settings:
                SettingsView()
            }
        }
    }
}

// NOTE: PlanningRootView has been removed. Planning items are now directly accessible from the sidebar
// as individual NavigationItems (.planningAgenda, .planningWork, .planningProjects, .planningChecklist).
// The pill navigation has been replaced with grouped sidebar sections.

/// Thin wrapper to host the Lessons root inside the main container.
struct LessonsMenuRootView: View {
    var body: some View {
        LessonsRootView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Sidebar with grouped sections (Source List style) for selecting navigation items.
private struct RootSidebar: View {
    @Binding var selection: RootView.NavigationItem

    var body: some View {
        #if os(macOS)
        List(selection: $selection) {
            // Section 1: Daily
            Section("Daily") {
                NavigationLink(value: RootView.NavigationItem.today) {
                    Label("Today", systemImage: "sun.max")
                }
                NavigationLink(value: RootView.NavigationItem.attendance) {
                    Label("Attendance", systemImage: "checklist")
                }
            }
            
            // Section 2: Classroom
            Section("Classroom") {
                NavigationLink(value: RootView.NavigationItem.students) {
                    Label("Students", systemImage: "person.3")
                }
                NavigationLink(value: RootView.NavigationItem.lessons) {
                    Label("Lessons", systemImage: "book")
                }
                NavigationLink(value: RootView.NavigationItem.community) {
                    Label("Community", systemImage: "bubble.left.and.bubble.right")
                }
                NavigationLink(value: RootView.NavigationItem.logs) {
                    Label("Logs", systemImage: "list.bullet")
                }
            }
            
            // Section 3: Planning
            Section("Planning") {
                NavigationLink(value: RootView.NavigationItem.planningChecklist) {
                    Label("Checklist", systemImage: "list.clipboard")
                }
                NavigationLink(value: RootView.NavigationItem.planningAgenda) {
                    Label("Presentations", systemImage: "calendar")
                }
                NavigationLink(value: RootView.NavigationItem.planningWork) {
                    Label("Open Work", systemImage: "tray.full")
                }
                NavigationLink(value: RootView.NavigationItem.planningProjects) {
                    Label("Projects", systemImage: "folder")
                }
            }
            
            // Section 4: System
            Section("System") {
                NavigationLink(value: RootView.NavigationItem.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .listStyle(.sidebar)
        #else
        // iOS/iPadOS: Use Buttons to avoid "Missing navigationDestination" errors
        List {
            // Section 1: Daily
            Section("Daily") {
                Button { selection = .today } label: {
                    Label("Today", systemImage: "sun.max")
                }
                .buttonStyle(.plain)
                
                Button { selection = .attendance } label: {
                    Label("Attendance", systemImage: "checklist")
                }
                .buttonStyle(.plain)
            }
            
            // Section 2: Classroom
            Section("Classroom") {
                Button { selection = .students } label: {
                    Label("Students", systemImage: "person.3")
                }
                .buttonStyle(.plain)
                
                Button { selection = .lessons } label: {
                    Label("Lessons", systemImage: "book")
                }
                .buttonStyle(.plain)
                
                Button { selection = .community } label: {
                    Label("Community", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.plain)
                
                Button { selection = .logs } label: {
                    Label("Logs", systemImage: "list.bullet")
                }
                .buttonStyle(.plain)
            }
            
            // Section 3: Planning
            Section("Planning") {
                Button { selection = .planningChecklist } label: {
                    Label("Checklist", systemImage: "list.clipboard")
                }
                .buttonStyle(.plain)
                
                Button { selection = .planningAgenda } label: {
                    Label("Presentations", systemImage: "calendar")
                }
                .buttonStyle(.plain)
                
                Button { selection = .planningWork } label: {
                    Label("Open Work", systemImage: "tray.full")
                }
                .buttonStyle(.plain)
                
                Button { selection = .planningProjects } label: {
                    Label("Projects", systemImage: "folder")
                }
                .buttonStyle(.plain)
            }
            
            // Section 4: System
            Section("System") {
                Button { selection = .settings } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
            }
        }
        #endif
    }
}

/// Compact iPhone tabs using a standard TabView with grouped navigation items.
private struct RootCompactTabs: View {
    @Binding var selectedNavItem: RootView.NavigationItem

    // Main tabs shown in bottom tab bar: Attendance, Today, Students
    private var mainTabs: [RootView.NavigationItem] {
        [.attendance, .today, .students, .community]
    }

    var body: some View {
        TabView(selection: Binding(
            get: { selectedNavItem.rawValue },
            set: { if let item = RootView.NavigationItem(rawValue: $0) { selectedNavItem = item } }
        )) {
            ForEach(mainTabs) { item in
                RootDetailContent(selectedNavItem: item)
                    .tabItem {
                        Label(item.displayName, systemImage: item.icon)
                    }
                    .tag(item.rawValue)
            }
        }
    }
}

/// More menu view for iPhone that shows additional navigation items
private struct MoreMenuView: View {
    @State private var navigationPath = NavigationPath()
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section("Classroom") {
                    Button {
                        navigationPath.append(RootView.NavigationItem.lessons)
                    } label: {
                        Label("Lessons", systemImage: RootView.NavigationItem.lessons.icon)
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(RootView.NavigationItem.community)
                    } label: {
                        Label("Community", systemImage: RootView.NavigationItem.community.icon)
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(RootView.NavigationItem.logs)
                    } label: {
                        Label("Logs", systemImage: RootView.NavigationItem.logs.icon)
                    }
                    .buttonStyle(.plain)
                }
                
                Section("Planning") {
                    Button {
                        navigationPath.append(RootView.NavigationItem.planningChecklist)
                    } label: {
                        Label("Checklist", systemImage: RootView.NavigationItem.planningChecklist.icon)
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(RootView.NavigationItem.planningAgenda)
                    } label: {
                        Label("Presentations", systemImage: RootView.NavigationItem.planningAgenda.icon)
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(RootView.NavigationItem.planningWork)
                    } label: {
                        Label("Open Work", systemImage: RootView.NavigationItem.planningWork.icon)
                    }
                    .buttonStyle(.plain)
                    Button {
                        navigationPath.append(RootView.NavigationItem.planningProjects)
                    } label: {
                        Label("Projects", systemImage: RootView.NavigationItem.planningProjects.icon)
                    }
                    .buttonStyle(.plain)
                }
                
                Section("System") {
                    Button {
                        navigationPath.append(RootView.NavigationItem.settings)
                    } label: {
                        Label("Settings", systemImage: RootView.NavigationItem.settings.icon)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: RootView.NavigationItem.self) { item in
                RootDetailContent(selectedNavItem: item)
            }
        }
    }
}

/// Warning banner displayed when using ephemeral/in-memory store.
/// Extracted to avoid type-checking complexity in the main body.
private struct EphemeralStoreWarningBanner: View {
    @Environment(\.appRouter) private var appRouter
    
    private var reason: String {
        UserDefaults.standard.string(forKey: UserDefaultsKeys.lastStoreErrorDescription) 
        ?? "The persistent store could not be opened. Data will not persist this session."
    }
    
    private var isInMemoryMode: Bool {
        reason.contains("in-memory") || reason.contains("temporary")
    }
    
    private var warningTitle: String {
        isInMemoryMode ? "⚠️ SAFE MODE: CHANGES WILL NOT BE SAVED" : "Warning: Data won't persist this session"
    }
    
    private var warningMessage: String {
        isInMemoryMode 
        ? "You are using an in-memory store. All data will be lost when you quit the app. Create a backup immediately!" 
        : reason
    }
    
    private var iconColor: Color {
        isInMemoryMode ? .red : .yellow
    }
    
    private var titleColor: Color {
        isInMemoryMode ? .red : .primary
    }
    
    private var backgroundColor: AnyShapeStyle {
        isInMemoryMode ? AnyShapeStyle(Color.red.opacity(0.1)) : AnyShapeStyle(.ultraThinMaterial)
    }
    
    private var borderColor: Color {
        isInMemoryMode ? Color.red.opacity(0.3) : Color.primary.opacity(0.1)
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(warningTitle)
                    .font(.callout)
                    .fontWeight(.bold)
                    .foregroundStyle(titleColor)
                Text(warningMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                appRouter.requestCreateBackup()
            } label: {
                Label("Backup Now", systemImage: "externaldrive.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(isInMemoryMode ? .red : nil)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundColor)
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(borderColor),
            alignment: .bottom
        )
    }
}

/// Warning banner displayed when CloudKit sync is enabled but not active.
private struct CloudKitSyncWarningBanner: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "icloud.slash")
                .foregroundStyle(.yellow)
            VStack(alignment: .leading, spacing: 2) {
                Text("⚠️ iCloud Sync Issue")
                    .font(.callout)
                    .fontWeight(.bold)
                Text("Sync is enabled but not currently active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.12))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(Color.yellow.opacity(0.3)),
            alignment: .bottom
        )
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}

