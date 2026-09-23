// RootDetailContent.swift
// Detail content routing for RootView - extracted for maintainability

import SwiftUI
import CoreData

/// Extracted detail content for RootView. Routes based on NavigationItem selection.
struct RootDetailContent: View {
    let selectedNavItem: RootView.NavigationItem
    @Environment(\.managedObjectContext) private var viewContext
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// The destination actually shown: an aliased case (`.note`, `.more`,
    /// `.perpetualCalendar`) renders as its target.
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
            case .today, .attendance, .note, .more:
                dailyContent
            case .students, .parentReports, .meetings, .goingOut:
                studentsContent
            case .lessons, .teachingAlbums, .stories, .bookClub, .planningChecklist,
                 .planningAgenda,
                 .planningProjects, .smallSequencePlanner:
                curriculumContent
            case .todos, .orders, .planningCalendar, .perpetualCalendar:
                planningContent
            case .progressDashboard, .curriculumMap, .lessonRecall:
                progressContent
            case .supplies, .procedures, .schedules,
                 .community, .resourceLibrary:
                resourcesContent
            case .askAI, .logs, .notes, .settings:
                toolsContent
            case .thisWeeksParsha:
                ThisWeeksParshaView()
            case .parshaCalendar:
                ParshaCalendarView()
            }
        }
    }

    private var dailyContent: AnyView {
        switch item {
        case .today: AnyView(TodayView(context: viewContext))
        case .attendance: AnyView(attendanceContent)
        default: AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private var planningContent: some View {
        switch item {
        case .todos: TodoMainView()
        case .orders: OrdersView()
        case .planningCalendar, .perpetualCalendar: PlanningCalendarView()
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
        case .lessons, .teachingAlbums, .stories, .bookClub, .planningChecklist,
             .planningAgenda:
            curriculumPlanningContent
        case .planningProjects, .smallSequencePlanner:
            curriculumAdvancedContent
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var curriculumPlanningContent: some View {
        switch item {
        case .lessons: LessonsMenuRootView()
        case .teachingAlbums: AlbumsRootView()
        case .stories: StoriesRootView()
        case .bookClub: BookClubRootView()
        case .planningChecklist: ClassAreaChecklistView()
        case .planningAgenda: WorksAgendaView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var curriculumAdvancedContent: some View {
        switch item {
        case .planningProjects: ProjectsRootView()
        case .smallSequencePlanner: SmallSequencePlannerView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var progressContent: some View {
        switch item {
        case .progressDashboard: ProgressDashboardView()
        case .curriculumMap: ClassCurriculumMapView()
        case .lessonRecall: RecallQueueView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var resourcesContent: some View {
        switch item {
        case .supplies: SuppliesListView()
        case .procedures: ProceduresListView()
        case .schedules: SchedulesView()
        case .community: CommunityMeetingsView()
        case .resourceLibrary: ResourceLibraryView()
        default: EmptyView()
        }
    }

    // Logs and Notes share one view type, so each gets its own identity or
    // switching between them would reuse the first and skip `onAppear`.
    private var toolsContent: AnyView {
        switch item {
        case .askAI: AnyView(ChatView())
        case .logs: AnyView(LogsMenuRootView().id(RootView.NavigationItem.logs))
        case .notes:
            AnyView(LogsMenuRootView(initialMode: .observations).id(RootView.NavigationItem.notes))
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
