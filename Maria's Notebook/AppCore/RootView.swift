// RootView.swift
// App root container with top pill navigation and tab routing.
// Behavior-preserving cleanup: comments and MARKs only.

import SwiftUI
import SwiftData
import Combine

/// Top-level container that manages app-wide navigation between Students, Albums, Planning, Today, Logs, and Settings.
struct RootView: View {
    // MARK: - Tabs
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
    @SceneStorage("RootView.selectedTab") private var selectedTabRaw: String = Tab.students.rawValue
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
    private var selectedTab: Tab {
        Tab(rawValue: selectedTabRaw) ?? .students
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
                    RootCompactTabs(selectedTabRaw: $selectedTabRaw)
                } else {
                    NavigationSplitView {
                        RootSidebar(selection: Binding(
                            get: { selectedTab },
                            set: { selectedTabRaw = $0.rawValue }
                        ))
                    } detail: {
                        RootDetailContent(selectedTab: selectedTab)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            #else
            NavigationSplitView {
                RootSidebar(selection: Binding(
                    get: { selectedTab },
                    set: { selectedTabRaw = $0.rawValue }
                ))
            } detail: {
                RootDetailContent(selectedTab: selectedTab)
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
            // Migrate legacy top-level Attendance tab to Students -> Attendance mode
            if Tab(rawValue: selectedTabRaw) == .attendance {
                selectedTabRaw = Tab.students.rawValue
                UserDefaults.standard.set("Attendance", forKey: "StudentsRootView.mode")
            }
            // Migrate legacy Lessons container to new top-level Albums tab
            if selectedTabRaw == "Lessons" {
                // If selectedTabRaw is "Lessons" (the old string), it might not match the new enum rawValue "Lessons".
                // But actually, we changed the enum rawValue to "Lessons" in this file.
                // However, if the stored value was "Albums" (old rawValue), we want to update it.
                if selectedTabRaw == "Albums" {
                    selectedTabRaw = Tab.albums.rawValue
                }
            }
            // Migrate legacy tab labels Lesson Planning -> Planning
            if selectedTabRaw == "Lesson Planning" {
                selectedTabRaw = Tab.planning.rawValue
            }
            // Migrate removal of Work Planning tab: route to Planning → Works Agenda
            if selectedTabRaw == "Work Planning" || selectedTabRaw == "Work" {
                selectedTabRaw = Tab.planning.rawValue
                UserDefaults.standard.set(PlanningRootView.Mode.works.rawValue, forKey: "PlanningRootView.mode")
            }
        }
        .onChange(of: appRouter.navigationDestination) { _, destination in
            if case .backfillIsPresented = destination {
                Task {
                    await backfillIsPresentedIfNeeded()
                }
                appRouter.clearNavigation()
            } else if case .openAttendance = destination {
                selectedTabRaw = Tab.students.rawValue
                UserDefaults.standard.set("Attendance", forKey: "StudentsRootView.mode")
                appRouter.clearNavigation()
            }
        }
        .onChange(of: appRouter.selectedTab) { _, tab in
            if let tab = tab {
                selectedTabRaw = tab.rawValue
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
                let sls = try modelContext.fetch(FetchDescriptor<StudentLesson>())
                let students = try modelContext.fetch(FetchDescriptor<Student>())
                let lessons = try modelContext.fetch(FetchDescriptor<Lesson>())
                let studentsByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
                let lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })

                var changed = false
                for sl in sls {
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
                let sls = try modelContext.fetch(FetchDescriptor<StudentLesson>())
                var changed = false
                for sl in sls {
                    if sl.givenAt != nil && sl.isPresented == false {
                        sl.isPresented = true
                        changed = true
                    }
                }
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
                let sls = try modelContext.fetch(FetchDescriptor<StudentLesson>())
                var fixed = 0
                for sl in sls {
                    let correct = sl.scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
                    if sl.scheduledForDay != correct {
                        sl.scheduledForDay = correct
                        fixed += 1
                    }
                }
                if fixed > 0 {
        #if DEBUG
                    print("Backfill.scheduledForDay: fixed \(fixed) records")
        #endif
                    _ = saveCoordinator.save(modelContext, reason: "Backfill data migration")
                }
                didBackfillScheduledForDay = true
        #if DEBUG
                print("Backfill.scheduledForDay: fixed \(fixed) records")
        #endif
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

/// Extracted detail content for RootView. Mirrors the original switch on selectedTab.
private struct RootDetailContent: View {
    let selectedTab: RootView.Tab
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            switch selectedTab {
            case .today:
                TodayView(context: modelContext) // Wires the Today hub
            case .albums:
                LessonsMenuRootView()
            case .students:
                StudentsRootView()
            case .planning:
                PlanningRootView()
            case .logs:
                LogsMenuRootView()
            case .attendance:
                AttendanceView()
            case .community:
                CommunityMeetingsView()
            case .settings:
                SettingsView()
            }
        }
    }
}

/// Container for Planning modes (Agenda, Works). Uses pill navigation and stores last mode in AppStorage.
struct PlanningRootView: View {
    // MARK: - Mode
    enum Mode: String, CaseIterable, Identifiable {
        case agenda = "Presentations"
        case works = "Open Work"
        case projects = "Projects"
        case checklist = "Checklist"
        var id: String { rawValue }
    }

    @AppStorage("PlanningRootView.mode") private var modeRaw: String = Mode.agenda.rawValue
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var mode: Mode { Mode(rawValue: modeRaw) ?? .agenda }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            Group {
                if horizontalSizeClass == .compact {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            PillButton(title: Mode.agenda.rawValue, isSelected: mode == .agenda) { modeRaw = Mode.agenda.rawValue }
                            PillButton(title: Mode.works.rawValue, isSelected: mode == .works) { modeRaw = Mode.works.rawValue }
                            PillButton(title: Mode.projects.rawValue, isSelected: mode == .projects) { modeRaw = Mode.projects.rawValue }
                            PillButton(title: Mode.checklist.rawValue, isSelected: mode == .checklist) { modeRaw = Mode.checklist.rawValue }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                } else {
                    HStack {
                        Spacer()
                        HStack(spacing: 12) {
                            PillButton(title: Mode.agenda.rawValue, isSelected: mode == .agenda) { modeRaw = Mode.agenda.rawValue }
                            PillButton(title: Mode.works.rawValue, isSelected: mode == .works) { modeRaw = Mode.works.rawValue }
                            PillButton(title: Mode.projects.rawValue, isSelected: mode == .projects) { modeRaw = Mode.projects.rawValue }
                            PillButton(title: Mode.checklist.rawValue, isSelected: mode == .checklist) { modeRaw = Mode.checklist.rawValue }
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
            #else
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    PillButton(title: Mode.agenda.rawValue, isSelected: mode == .agenda) { modeRaw = Mode.agenda.rawValue }
                    PillButton(title: Mode.works.rawValue, isSelected: mode == .works) { modeRaw = Mode.works.rawValue }
                    PillButton(title: Mode.projects.rawValue, isSelected: mode == .projects) { modeRaw = Mode.projects.rawValue }
                    PillButton(title: Mode.checklist.rawValue, isSelected: mode == .checklist) { modeRaw = Mode.checklist.rawValue }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            #endif

            Divider()

            Group {
                if mode == .agenda {
                    PresentationsView()
                } else if mode == .works {
                    WorksAgendaView()
                } else if mode == .projects {
                    NavigationStack {
                        ProjectsRootView()
                    }
                }
                else if mode == .checklist {
                    ClassSubjectChecklistView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Migrate legacy stored mode labels to new ones
                if modeRaw == "Agenda" { modeRaw = Mode.agenda.rawValue }
                if modeRaw == "Board" { modeRaw = Mode.agenda.rawValue }
                if modeRaw == "Lessons Board" { modeRaw = Mode.agenda.rawValue }
                if modeRaw == "Lessons Agenda (Beta)" { modeRaw = Mode.agenda.rawValue }
                if modeRaw == "Lessons Agenda" { modeRaw = Mode.agenda.rawValue }
                if modeRaw == "Presentations Agenda" { modeRaw = Mode.agenda.rawValue }
                
                if modeRaw == "Work Agenda (Beta)" { modeRaw = Mode.works.rawValue }
                if modeRaw == "Work Agenda" { modeRaw = Mode.works.rawValue }
                
                if modeRaw == "Book Clubs" { modeRaw = Mode.projects.rawValue }
                if modeRaw == "Projects" { modeRaw = Mode.projects.rawValue }
                
                if modeRaw == "Class Checklist" { modeRaw = Mode.checklist.rawValue }
                
                // Migrate LessonsAgendaBeta.startDate -> LessonsAgenda.startDate (one-time)
                let oldKey = "LessonsAgendaBeta.startDate"
                let newKey = "LessonsAgenda.startDate"
                if UserDefaults.standard.double(forKey: newKey) == 0 {
                    let old = UserDefaults.standard.double(forKey: oldKey)
                    if old != 0 {
                        UserDefaults.standard.set(old, forKey: newKey)
                        // Optionally clear old key
                        // UserDefaults.standard.removeObject(forKey: oldKey)
                    }
                }
            }
        }
    }
}

/// Thin wrapper to host the Lessons root inside the main container.
struct LessonsMenuRootView: View {
    var body: some View {
        LessonsRootView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Sidebar list for selecting a root tab. Excludes the legacy Attendance tab.
private struct RootSidebar: View {
    @Binding var selection: RootView.Tab

    private var tabs: [RootView.Tab] {
        RootView.Tab.allCases.filter { $0 != .attendance }
    }

    var body: some View {
        #if os(macOS)
        List(selection: $selection) {
            ForEach(tabs) { tab in
                Label(tab.rawValue, systemImage: tab.icon)
                    .tag(tab)
            }
        }
        #else
        List {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                } label: {
                    Label(tab.rawValue, systemImage: tab.icon)
                }
                .buttonStyle(.plain)
            }
        }
        #endif
    }
}

/// Compact iPhone tabs using a standard TabView. Excludes legacy Attendance tab.
private struct RootCompactTabs: View {
    // Bind to RootView's selected tab state via the raw string value
    @Binding var selectedTabRaw: String

    private var tabs: [RootView.Tab] {
        RootView.Tab.allCases.filter { $0 != .attendance }
    }

    var body: some View {
        TabView(selection: $selectedTabRaw) {
            ForEach(tabs) { tab in
                RootDetailContent(selectedTab: tab)
                    .tabItem {
                        Label(tab.rawValue, systemImage: tab.icon)
                    }
                    .tag(tab.rawValue)
            }
        }
    }
}

#Preview {
    RootView()
        .previewEnvironment()
}

