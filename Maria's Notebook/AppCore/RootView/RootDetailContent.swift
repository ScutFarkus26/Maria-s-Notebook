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
            case .today, .attendance, .workCycle, .note, .todos, .fridayReview:
                dailyContent
            case .students, .meetings, .goingOut, .parentCommunication, .classroomJobs, .more:
                studentsContent
            case .lessons, .stories, .planningChecklist, .planningAgenda, .planningWork,
                 .planningProgression, .planningProjects, .needsLesson, .smallGroupPlanner:
                curriculumContent
            case .progressDashboard, .lessonFrequency, .curriculumBalance,
                 .greatLessonsTimeline, .transitionPlanner, .threeYearCycle:
                progressContent
            case .supplies, .procedures, .schedules, .perpetualCalendar,
                 .prepChecklist, .community, .issues, .resourceLibrary:
                resourcesContent
            case .askAI, .logs, .settings:
                toolsContent
            case .thisWeeksParsha:
                ThisWeeksParshaView()
            case .parshaCalendar:
                ParshaCalendarView()
            case .parshaAlbumMatches:
                ParshaAlbumSuggestionsView()
            case .parshaCoverage:
                ParshaCoverageView()
            case .parshaTopics:
                ParshaTopicBrowserView()
            }
        }
    }

    private var dailyContent: AnyView {
        switch selectedNavItem {
        case .today: AnyView(TodayView(context: viewContext))
        case .attendance: AnyView(attendanceContent)
        case .workCycle: AnyView(WorkCycleView())
        case .note: AnyView(noteTabContent)
        case .todos: AnyView(TodoMainView())
        case .fridayReview: AnyView(FridayReviewView())
        default: AnyView(EmptyView())
        }
    }

    @ViewBuilder
    private var studentsContent: some View {
        switch selectedNavItem {
        case .students: StudentsRootView()
        case .meetings: MeetingsWorkflowView()
        case .goingOut: GoingOutRootView()
        case .parentCommunication: ParentCommunicationRootView()
        case .classroomJobs: ClassroomJobsRootView()
        case .more: MoreMenuView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var curriculumContent: some View {
        switch selectedNavItem {
        case .lessons, .stories, .planningChecklist, .planningAgenda, .planningWork:
            curriculumPlanningContent
        case .planningProgression, .planningProjects, .needsLesson, .smallGroupPlanner:
            curriculumAdvancedContent
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var curriculumPlanningContent: some View {
        switch selectedNavItem {
        case .lessons: LessonsMenuRootView()
        case .stories: StoriesRootView()
        case .planningChecklist: ClassSubjectChecklistView()
        case .planningAgenda: PresentationsView()
        case .planningWork: WorksAgendaView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var curriculumAdvancedContent: some View {
        switch selectedNavItem {
        case .planningProgression: ProgressionRootView()
        case .planningProjects: ProjectsRootView()
        case .needsLesson: NeedsLessonView()
        case .smallGroupPlanner: SmallGroupPlannerView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var progressContent: some View {
        switch selectedNavItem {
        case .progressDashboard, .lessonFrequency, .curriculumBalance:
            progressAnalyticsContent
        case .greatLessonsTimeline, .transitionPlanner, .threeYearCycle:
            progressTimelineContent
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var progressAnalyticsContent: some View {
        switch selectedNavItem {
        case .progressDashboard: ProgressDashboardView()
        case .lessonFrequency: LessonFrequencyView()
        case .curriculumBalance: CurriculumBalanceView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var progressTimelineContent: some View {
        switch selectedNavItem {
        case .greatLessonsTimeline: GreatLessonsTimelineView()
        case .transitionPlanner: TransitionPlannerRootView()
        case .threeYearCycle: ThreeYearCycleView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var resourcesContent: some View {
        switch selectedNavItem {
        case .supplies: SuppliesListView()
        case .procedures: ProceduresListView()
        case .schedules: SchedulesView()
        case .perpetualCalendar: PerpetualCalendarView()
        case .prepChecklist: PrepChecklistRootView()
        case .community: CommunityMeetingsView()
        case .issues: IssuesListView()
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
