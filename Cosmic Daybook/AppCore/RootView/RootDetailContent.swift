// RootDetailContent.swift
// Detail content routing for RootView - extracted for maintainability

import SwiftUI
import CoreData

/// Extracted detail content for RootView. Routes based on NavigationItem selection.
struct RootDetailContent: View {
    let selectedNavItem: RootView.NavigationItem
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// The destination actually shown: an aliased case (`.note`, `.logs`,
    /// `.curriculumMap`, `.stories`…) renders as its target, which opens on the
    /// alias's view through `AppRouter.screenLanding`.
    private var item: RootView.NavigationItem { selectedNavItem.canonical }

    /// Returns true if we're on iPhone compact layout
    private var isIPhoneCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        Group {
            switch item {
            case .today, .attendance:
                dailyContent
            case .students, .parentReports, .meetings, .goingOut:
                studentsContent
            case .lessons, .teachingAlbums, .planningChecklist, .planningAgenda,
                 .planningProjects, .smallSequencePlanner:
                curriculumContent
            case .todos, .planningCalendar:
                planningContent
            case .supplies, .schedules, .community, .resourceLibrary:
                resourcesContent
            case .notes, .settings:
                toolsContent
            case .thisWeeksParsha:
                ThisWeeksParshaView()
            // Aliases: `item` is canonical, so these never get here.
            case .note, .more, .perpetualCalendar, .orders, .logs, .curriculumMap,
                 .progressDashboard, .lessonRecall, .parshaCalendar, .stories, .procedures,
                 .bookClub, .askAI:
                EmptyView()
            }
        }
    }

    // Today is rebuilt on every pass of this body; `TodayRootView` makes its
    // view model once, when the screen first appears, not per rebuild.
    private var dailyContent: AnyView {
        switch item {
        case .today: AnyView(TodayRootView())
        case .attendance: AnyView(attendanceContent)
        default: AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private var planningContent: some View {
        switch item {
        case .todos: TodoMainView()
        case .planningCalendar: PlanningCalendarView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var studentsContent: some View {
        switch item {
        case .students: StudentsView()
        case .parentReports: ParentReportsQueueView()
        case .meetings: MeetingsWorkflowView()
        case .goingOut: GoingOutRootView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var curriculumContent: some View {
        switch item {
        case .lessons: LessonsMenuRootView()
        case .teachingAlbums: AlbumsRootView()
        case .planningChecklist: ClassGridView()
        case .planningAgenda: WorksAgendaView()
        case .planningProjects: ProjectsRootView()
        case .smallSequencePlanner: GroupsView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var resourcesContent: some View {
        switch item {
        case .supplies: RestockView()
        case .schedules: SchedulesView()
        case .community: CommunityMeetingsView()
        case .resourceLibrary: ResourcesView()
        default: EmptyView()
        }
    }

    private var toolsContent: AnyView {
        switch item {
        case .notes: AnyView(ObservationsView())
        case .settings: AnyView(SettingsView())
        default: AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private var attendanceContent: some View {
        if isIPhoneCompact {
            AttendanceStandaloneView()
        } else {
            AttendanceMacView()
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

// `RootAdaptiveTabs` (iOS-only) lives in `RootAdaptiveTabs.swift`.
