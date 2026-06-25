// RootDetailContent.swift
// Detail content routing for RootView - extracted for maintainability

import SwiftUI
import CoreData

/// Extracted detail content for RootView. Routes based on NavigationItem selection.
struct RootDetailContent: View {
    let selectedNavItem: RootView.NavigationItem
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.appRouter) private var appRouter
    @State private var isShowingQuickNote = false
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

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
            switch selectedNavItem {
            case .today, .attendance, .note:
                dailyContent
            case .students, .meetings, .goingOut, .more:
                studentsContent
            case .lessons, .stories, .bookClub, .planningChecklist, .planningAgenda, .planningWork,
                 .planningProjects, .needsLesson, .smallSequencePlanner:
                curriculumContent
            case .todos, .planningCalendar, .perpetualCalendar:
                planningContent
            case .progressDashboard, .lessonRecall:
                progressContent
            case .supplies, .procedures, .schedules,
                 .community, .resourceLibrary:
                resourcesContent
            case .askAI, .logs, .settings:
                toolsContent
            case .thisWeeksParsha:
                ThisWeeksParshaView()
            case .parshaCalendar:
                ParshaCalendarView()
            }
        }
    }

    private var dailyContent: AnyView {
        switch selectedNavItem {
        case .today: AnyView(TodayView(context: viewContext))
        case .attendance: AnyView(attendanceContent)
        case .note: AnyView(noteTabContent)
        default: AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private var planningContent: some View {
        switch selectedNavItem {
        case .todos: TodoMainView()
        case .planningCalendar, .perpetualCalendar: PlanningCalendarView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var studentsContent: some View {
        switch selectedNavItem {
        case .students: StudentsView()
        case .meetings: MeetingsWorkflowView()
        case .goingOut: GoingOutRootView()
        case .more: MoreMenuView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var curriculumContent: some View {
        switch selectedNavItem {
        case .lessons, .stories, .bookClub, .planningChecklist, .planningAgenda, .planningWork:
            curriculumPlanningContent
        case .planningProjects, .needsLesson, .smallSequencePlanner:
            curriculumAdvancedContent
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var curriculumPlanningContent: some View {
        switch selectedNavItem {
        case .lessons: LessonsMenuRootView()
        case .stories: StoriesRootView()
        case .bookClub: BookClubRootView()
        case .planningChecklist: ClassAreaChecklistView()
        case .planningAgenda: PresentationsView()
        case .planningWork: WorksAgendaView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var curriculumAdvancedContent: some View {
        switch selectedNavItem {
        case .planningProjects: ProjectsRootView()
        case .needsLesson: NeedsLessonView()
        case .smallSequencePlanner: SmallSequencePlannerView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var progressContent: some View {
        switch selectedNavItem {
        case .progressDashboard: ProgressDashboardView()
        case .lessonRecall: RecallQueueView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var resourcesContent: some View {
        switch selectedNavItem {
        case .supplies: SuppliesListView()
        case .procedures: ProceduresListView()
        case .schedules: SchedulesView()
        case .community: CommunityMeetingsView()
        case .resourceLibrary: ResourceLibraryView()
        default: EmptyView()
        }
    }

    private var toolsContent: AnyView {
        switch selectedNavItem {
        case .askAI: AnyView(ChatView())
        case .logs: AnyView(LogsMenuRootView())
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

    private var noteTabContent: some View {
        Color.clear
            .onAppear {
                isShowingQuickNote = true
            }
            .sheet(isPresented: $isShowingQuickNote) {
                QuickNoteSheet()
                    .onDisappear {
                        appRouter.navigateTo(.today)
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

// `RootAdaptiveTabs` (iOS-only) lives in `RootAdaptiveTabs.swift`.
// `MoreMenuView` lives in `MoreMenuView.swift`.
