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
        case albums = "Albums" // Albums
        case planning = "Planning"
        case today = "Today"
        case logs = "Logs"
        case attendance = "Attendance"
        case community = "Community Meetings"
        case settings = "Settings"

        var id: String { rawValue }
    }

    // MARK: - Storage
    @SceneStorage("RootView.selectedTab") private var selectedTabRaw: String = Tab.students.rawValue
    @Environment(\.modelContext) private var modelContext
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
    
    private var pillTabs: [Tab] { Tab.allCases.filter { $0 != .attendance } }

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
                        NotificationCenter.default.post(name: Notification.Name("CreateBackupRequested"), object: nil)
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

            // Top pill navigation
            #if os(iOS)
            Group {
                if horizontalSizeClass == .compact {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(pillTabs) { tab in
                                Button {
                                    selectedTabRaw = tab.rawValue
                                } label: {
                                    Text(tab.rawValue)
                                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .frame(minHeight: 30)
                                        .background(pillBackground(for: tab))
                                        .foregroundStyle(pillForeground(for: tab))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                } else {
                    HStack {
                        Spacer()
                        HStack(spacing: 12) {
                            ForEach(pillTabs) { tab in
                                Button {
                                    selectedTabRaw = tab.rawValue
                                } label: {
                                    Text(tab.rawValue)
                                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
                                        .lineLimit(1)
                                        .fixedSize(horizontal: true, vertical: false)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 8)
                                        .frame(minHeight: 30)
                                        .background(pillBackground(for: tab))
                                        .foregroundStyle(pillForeground(for: tab))
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
            }
            #else
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    ForEach(pillTabs) { tab in
                        Button {
                            selectedTabRaw = tab.rawValue
                        } label: {
                            Text(tab.rawValue)
                                .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 8)
                                .frame(minHeight: 30)
                                .background(pillBackground(for: tab))
                                .foregroundStyle(pillForeground(for: tab))
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 8)
            #endif

            Divider()

            // Active view
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            backfillRelationshipsIfNeeded()
            backfillIsPresentedIfNeeded()
            backfillScheduledForDayIfNeeded()
            // Migrate legacy top-level Attendance tab to Students -> Attendance mode
            if Tab(rawValue: selectedTabRaw) == .attendance {
                selectedTabRaw = Tab.students.rawValue
                UserDefaults.standard.set("Attendance", forKey: "StudentsRootView.mode")
            }
            // Migrate legacy Lessons container to new top-level Albums tab
            if selectedTabRaw == "Lessons" {
                selectedTabRaw = Tab.albums.rawValue
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BackfillIsPresentedRequested"))) { _ in
            backfillIsPresentedIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("OpenAttendanceRequested"))) { _ in
            selectedTabRaw = Tab.students.rawValue
            UserDefaults.standard.set("Attendance", forKey: "StudentsRootView.mode")
        }
        .saveErrorAlert()
#if os(macOS)
        .background(EnsureResizableWindow(minSize: NSSize(width: 900, height: 600)))
#endif
    }

    // MARK: - Styling

    private func pillBackground(for tab: Tab) -> some ShapeStyle {
        if tab == selectedTab {
            return AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(Color.secondary.opacity(0.12))
        }
    }

    private func pillForeground(for tab: Tab) -> some ShapeStyle {
        if tab == selectedTab {
            return AnyShapeStyle(Color.white)
        } else {
            return AnyShapeStyle(Color.primary)
        }
    }

    // MARK: - Backfill

    private func backfillRelationshipsIfNeeded() {
        guard !didBackfillRelationships else { return }
        do {
            let sls = try modelContext.fetch(FetchDescriptor<StudentLesson>())
            let students = try modelContext.fetch(FetchDescriptor<Student>())
            let lessons = try modelContext.fetch(FetchDescriptor<Lesson>())
            let studentsByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
            let lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })

            var changed = false
            for sl in sls {
                let targetLesson = lessonsByID[sl.lessonID]
                let targetStudents = sl.studentIDs.compactMap { studentsByID[$0] }
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

    private func backfillIsPresentedIfNeeded() {
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
    
    private func backfillScheduledForDayIfNeeded() {
        guard !didBackfillScheduledForDay else { return }
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
    
    // MARK: - State
}

/// Container for Planning modes (Agenda, Works). Uses pill navigation and stores last mode in AppStorage.
struct PlanningRootView: View {
    // MARK: - Mode
    enum Mode: String, CaseIterable, Identifiable {
        case agenda = "Lessons Agenda"
        case works = "Work Agenda"
        case followUpInbox = "Follow-Up Inbox"
        case bookClubs = "Book Clubs"
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
                            PillNavButton(title: Mode.agenda.rawValue, isSelected: mode == .agenda) { modeRaw = Mode.agenda.rawValue }
                            PillNavButton(title: Mode.works.rawValue, isSelected: mode == .works) { modeRaw = Mode.works.rawValue }
                            PillNavButton(title: Mode.followUpInbox.rawValue, isSelected: mode == .followUpInbox) { modeRaw = Mode.followUpInbox.rawValue }
                            PillNavButton(title: Mode.bookClubs.rawValue, isSelected: mode == .bookClubs) { modeRaw = Mode.bookClubs.rawValue }
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
                            PillNavButton(title: Mode.agenda.rawValue, isSelected: mode == .agenda) { modeRaw = Mode.agenda.rawValue }
                            PillNavButton(title: Mode.works.rawValue, isSelected: mode == .works) { modeRaw = Mode.works.rawValue }
                            PillNavButton(title: Mode.followUpInbox.rawValue, isSelected: mode == .followUpInbox) { modeRaw = Mode.followUpInbox.rawValue }
                            PillNavButton(title: Mode.bookClubs.rawValue, isSelected: mode == .bookClubs) { modeRaw = Mode.bookClubs.rawValue }
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
                    PillNavButton(title: Mode.agenda.rawValue, isSelected: mode == .agenda) { modeRaw = Mode.agenda.rawValue }
                    PillNavButton(title: Mode.works.rawValue, isSelected: mode == .works) { modeRaw = Mode.works.rawValue }
                    PillNavButton(title: Mode.followUpInbox.rawValue, isSelected: mode == .followUpInbox) { modeRaw = Mode.followUpInbox.rawValue }
                    PillNavButton(title: Mode.bookClubs.rawValue, isSelected: mode == .bookClubs) { modeRaw = Mode.bookClubs.rawValue }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            #endif

            Divider()

            Group {
                if mode == .agenda {
                    LessonsAgendaBetaView()
                } else if mode == .works {
                    WorksAgendaView()
                } else if mode == .followUpInbox {
                    FollowUpInboxView()
                } else if mode == .bookClubs {
                    BookClubsRootView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Migrate legacy stored mode labels to new ones
                if modeRaw == "Agenda" {
                    modeRaw = Mode.agenda.rawValue
                }
                if modeRaw == "Board" {
                    modeRaw = Mode.agenda.rawValue
                }
                if modeRaw == "Lessons Board" {
                    modeRaw = Mode.agenda.rawValue
                }
                if modeRaw == "Lessons Agenda (Beta)" {
                    modeRaw = Mode.agenda.rawValue
                }
                if modeRaw == "Work Agenda (Beta)" { modeRaw = Mode.works.rawValue }
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

#Preview {
    RootView()
        .previewEnvironment()
}

