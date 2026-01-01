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
        case students
        case lessons // Previously "Albums"
        
        // Planning Sub-items (Promoted from PlanningRootView pills)
        case planningAgenda
        case planningWork
        case planningProjects
        case planningChecklist
        
        case logs
        case community
        case settings
        
        var id: Self { self }
        
        var displayName: String {
            switch self {
            case .today: return "Today"
            case .attendance: return "Attendance"
            case .students: return "Students"
            case .lessons: return "Lessons"
            case .planningAgenda: return "Presentations"
            case .planningWork: return "Open Work"
            case .planningProjects: return "Projects"
            case .planningChecklist: return "Checklist"
            case .logs: return "Logs"
            case .community: return "Community Meetings"
            case .settings: return "Settings"
            }
        }
        
        var icon: String {
            switch self {
            case .today: return "sun.max"
            case .attendance: return "checklist"
            case .students: return "person.3"
            case .lessons: return "book"
            case .planningAgenda: return "calendar"
            case .planningWork: return "tray.full"
            case .planningProjects: return "folder"
            case .planningChecklist: return "list.clipboard"
            case .logs: return "list.bullet"
            case .community: return "bubble.left.and.bubble.right"
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
            case .logs: self = .logs
            case .community: self = .community
            case .settings: self = .settings
            }
        }
        
        // Helper to convert legacy Tab for backward compatibility
        var legacyTab: Tab? {
            switch self {
            case .today: return .today
            case .attendance: return .attendance
            case .students: return .students
            case .lessons: return .albums
            case .planningAgenda, .planningWork, .planningProjects, .planningChecklist: return .planning
            case .logs: return .logs
            case .community: return .community
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
        case community = "Community Meetings"
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
    @EnvironmentObject private var saveCoordinator: SaveCoordinator
    @AppStorage("Backfill.relationships.v1") private var didBackfillRelationships: Bool = false
    @AppStorage("Backfill.isPresentedFromGivenAt.v1") private var didBackfillIsPresented: Bool = false
    @AppStorage("Backfill.scheduledForDay.v1") private var didBackfillScheduledForDay: Bool = false
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
                if let modeRaw = UserDefaults.standard.string(forKey: "PlanningRootView.mode") {
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
            if UserDefaults.standard.bool(forKey: MariasToolboxApp.ephemeralSessionFlagKey) {
                let reason = UserDefaults.standard.string(forKey: MariasToolboxApp.lastStoreErrorDescriptionKey) ?? "The persistent store could not be opened. Data will not persist this session."
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Warning: Data won't persist this session").font(.callout).fontWeight(.semibold)
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        appRouter.requestCreateBackup()
                    } label: {
                        Label("Backup Now", systemImage: "externaldrive.badge.plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.primary.opacity(0.1)), alignment: .bottom)
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
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #endif
        }
        .task {
            // Run backfill operations asynchronously to avoid blocking UI
            // These are one-time migrations that must complete, but don't need to block the view
            await backfillRelationshipsIfNeeded()
            await backfillIsPresentedIfNeeded()
            await backfillScheduledForDayIfNeeded()
        }
        .onAppear {
            // Migration: Convert legacy selectedTab to selectedNavItem if needed
            if selectedNavItemRaw == nil, let legacyRaw = selectedTabRaw {
                if let legacyTab = Tab(rawValue: legacyRaw) {
                    if let navItem = NavigationItem(fromLegacyTab: legacyTab) {
                        // For planning, check stored mode
                        if legacyTab == .planning {
                            if let modeRaw = UserDefaults.standard.string(forKey: "PlanningRootView.mode") {
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
            if case .backfillIsPresented = destination {
                Task {
                    await backfillIsPresentedIfNeeded()
                }
                appRouter.clearNavigation()
            } else if case .openAttendance = destination {
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
    #if os(macOS)
        .background(EnsureResizableWindow(minSize: NSSize(width: 900, height: 600)))
    #endif
    }

    // MARK: - Backfill
    
    // These backfill operations are one-time migrations that preserve all functionality.
    // Made async to avoid blocking UI, but they still complete fully.

    private func backfillRelationshipsIfNeeded() async {
        guard !didBackfillRelationships else { return }
        // Run on main actor since we're using modelContext (SwiftData requirement)
        await MainActor.run {
            do {
                // OPTIMIZATION: Fetch all data once (these are relatively small lookups)
                let sls = try modelContext.fetch(FetchDescriptor<StudentLesson>())
                let students = try modelContext.fetch(FetchDescriptor<Student>())
                let lessons = try modelContext.fetch(FetchDescriptor<Lesson>())
                let studentsByID = students.toDictionary(by: \.id)
                let lessonsByID = lessons.toDictionary(by: \.id)

                // OPTIMIZATION: Process in batches and save periodically to avoid memory pressure
                // For large datasets, process in chunks of 1000
                let batchSize = 1000
                var changed = false
                var processed = 0
                
                for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, sls.count)
                    let batch = Array(sls[batchStart..<batchEnd])
                    
                    for sl in batch {
                        // CloudKit compatibility: Convert String lessonID to UUID for lookup
                        guard let lessonIDUUID = UUID(uuidString: sl.lessonID) else { continue }
                        let targetLesson = lessonsByID[lessonIDUUID]
                        let targetStudents: [Student] = sl.studentIDs.compactMap { idString in
                            guard let id = UUID(uuidString: idString) else { return nil }
                            return studentsByID[id]
                        }
                        if sl.lesson?.id != targetLesson?.id { sl.lesson = targetLesson; changed = true }
                        let currentIDs = Set(sl.students.map { $0.id })
                        let targetIDs = Set(targetStudents.map { $0.id })
                        if currentIDs != targetIDs {
                            sl.students = targetStudents
                            changed = true
                        }
                        if changed {
                            sl.syncSnapshotsFromRelationships()
                        }
                    }
                    
                    processed += batch.count
                    // Save periodically to avoid holding too many changes in memory
                    if changed && processed % batchSize == 0 {
                        _ = saveCoordinator.save(modelContext, reason: "Backfill data migration (batch)")
                        changed = false // Reset for next batch
                    }
                }
                
                // Final save if there are remaining changes
                if changed {
                    _ = saveCoordinator.save(modelContext, reason: "Backfill data migration")
                }
                didBackfillRelationships = true
            } catch {
                // If backfill fails, skip and try again next launch
            }
        }
    }

    private func backfillIsPresentedIfNeeded() async {
        await MainActor.run {
            do {
                // OPTIMIZATION: Process in batches for large datasets
                let sls = try modelContext.fetch(FetchDescriptor<StudentLesson>())
                let batchSize = 1000
                var changed = false
                
                for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, sls.count)
                    let batch = Array(sls[batchStart..<batchEnd])
                    
                    for sl in batch {
                        if sl.givenAt != nil && sl.isPresented == false {
                            sl.isPresented = true
                            changed = true
                        }
                    }
                    
                    // Save periodically
                    if changed && (batchEnd % batchSize == 0 || batchEnd == sls.count) {
                        _ = saveCoordinator.save(modelContext, reason: "Backfill data migration (batch)")
                        changed = false
                    }
                }
                
                // Final save if needed
                if changed {
                    _ = saveCoordinator.save(modelContext, reason: "Backfill data migration")
                }
            } catch {
                // If backfill fails, skip and try again next launch
            }
        }
    }
    
    private func backfillScheduledForDayIfNeeded() async {
        guard !didBackfillScheduledForDay else { return }
        await MainActor.run {
            do {
                // OPTIMIZATION: Process in batches for large datasets
                let sls = try modelContext.fetch(FetchDescriptor<StudentLesson>())
                let batchSize = 1000
                var fixed = 0
                var needsSave = false
                
                for batchStart in stride(from: 0, to: sls.count, by: batchSize) {
                    let batchEnd = min(batchStart + batchSize, sls.count)
                    let batch = Array(sls[batchStart..<batchEnd])
                    
                    for sl in batch {
                        let correct = sl.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
                        if sl.scheduledForDay != correct {
                            sl.scheduledForDay = correct
                            fixed += 1
                            needsSave = true
                        }
                    }
                    
                    // Save periodically
                    if needsSave && (batchEnd % batchSize == 0 || batchEnd == sls.count) {
                        _ = saveCoordinator.save(modelContext, reason: "Backfill data migration (batch)")
                        needsSave = false
                    }
                }
                
                if fixed > 0 {
        #if DEBUG
                    print("Backfill.scheduledForDay: fixed \(fixed) records")
        #endif
                    if needsSave {
                        _ = saveCoordinator.save(modelContext, reason: "Backfill data migration")
                    }
                }
                didBackfillScheduledForDay = true
            } catch {
                didBackfillScheduledForDay = true
        #if DEBUG
                print("Backfill.scheduledForDay: fixed 0 records due to error")
        #endif
            }
        }
    }
    
    // MARK: - State
}

/// Extracted detail content for RootView. Routes based on NavigationItem selection.
private struct RootDetailContent: View {
    let selectedNavItem: RootView.NavigationItem
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            switch selectedNavItem {
            case .today:
                TodayView(context: modelContext)
            case .attendance:
                AttendanceView()
            case .students:
                StudentsRootView()
            case .lessons:
                LessonsMenuRootView()
            case .planningAgenda:
                PresentationsView()
            case .planningWork:
                WorksAgendaView()
            case .planningProjects:
                NavigationStack {
                    ProjectsRootView()
                }
            case .planningChecklist:
                ClassSubjectChecklistView()
            case .logs:
                LogsMenuRootView()
            case .community:
                CommunityMeetingsView()
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
            }
            
            // Section 3: Planning (Expanded)
            Section("Planning") {
                NavigationLink(value: RootView.NavigationItem.planningAgenda) {
                    Label("Presentations", systemImage: "calendar")
                }
                NavigationLink(value: RootView.NavigationItem.planningWork) {
                    Label("Open Work", systemImage: "tray.full")
                }
                NavigationLink(value: RootView.NavigationItem.planningProjects) {
                    Label("Projects", systemImage: "folder")
                }
                NavigationLink(value: RootView.NavigationItem.planningChecklist) {
                    Label("Checklist", systemImage: "list.clipboard")
                }
            }
            
            // Section 4: System
            Section("System") {
                NavigationLink(value: RootView.NavigationItem.logs) {
                    Label("Logs", systemImage: "list.bullet")
                }
                NavigationLink(value: RootView.NavigationItem.community) {
                    Label("Community Meetings", systemImage: "bubble.left.and.bubble.right")
                }
                NavigationLink(value: RootView.NavigationItem.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .listStyle(.sidebar)
        #else
        List {
            // Section 1: Daily
            Section("Daily") {
                Button {
                    selection = .today
                } label: {
                    Label("Today", systemImage: "sun.max")
                }
                .buttonStyle(.plain)
                
                Button {
                    selection = .attendance
                } label: {
                    Label("Attendance", systemImage: "checklist")
                }
                .buttonStyle(.plain)
            }
            
            // Section 2: Classroom
            Section("Classroom") {
                Button {
                    selection = .students
                } label: {
                    Label("Students", systemImage: "person.3")
                }
                .buttonStyle(.plain)
                
                Button {
                    selection = .lessons
                } label: {
                    Label("Lessons", systemImage: "book")
                }
                .buttonStyle(.plain)
            }
            
            // Section 3: Planning
            Section("Planning") {
                Button {
                    selection = .planningAgenda
                } label: {
                    Label("Presentations", systemImage: "calendar")
                }
                .buttonStyle(.plain)
                
                Button {
                    selection = .planningWork
                } label: {
                    Label("Open Work", systemImage: "tray.full")
                }
                .buttonStyle(.plain)
                
                Button {
                    selection = .planningProjects
                } label: {
                    Label("Projects", systemImage: "folder")
                }
                .buttonStyle(.plain)
                
                Button {
                    selection = .planningChecklist
                } label: {
                    Label("Checklist", systemImage: "list.clipboard")
                }
                .buttonStyle(.plain)
            }
            
            // Section 4: System
            Section("System") {
                Button {
                    selection = .logs
                } label: {
                    Label("Logs", systemImage: "list.bullet")
                }
                .buttonStyle(.plain)
                
                Button {
                    selection = .community
                } label: {
                    Label("Community Meetings", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.plain)
                
                Button {
                    selection = .settings
                } label: {
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

    private var navItems: [RootView.NavigationItem] {
        // Order: Daily, Classroom, Planning, System
        [.today, .attendance, .students, .lessons, .planningAgenda, .planningWork, .planningProjects, .planningChecklist, .logs, .community, .settings]
    }

    var body: some View {
        TabView(selection: Binding(
            get: { selectedNavItem.rawValue },
            set: { if let item = RootView.NavigationItem(rawValue: $0) { selectedNavItem = item } }
        )) {
            ForEach(navItems) { item in
                RootDetailContent(selectedNavItem: item)
                    .tabItem {
                        Label(item.displayName, systemImage: item.icon)
                    }
                    .tag(item.rawValue)
            }
        }
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}

