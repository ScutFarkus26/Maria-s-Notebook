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
            case .lessons, .planningChecklist, .planningAgenda, .planningWork,
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
            }
        }
    }

    @ViewBuilder
    private var dailyContent: some View {
        switch selectedNavItem {
        case .today: TodayView(context: viewContext)
        case .attendance: attendanceContent
        case .workCycle: WorkCycleView()
        case .note: noteTabContent
        case .todos: TodoMainView()
        case .fridayReview: FridayReviewView()
        default: EmptyView()
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
        case .lessons, .planningChecklist, .planningAgenda, .planningWork:
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

    @ViewBuilder
    private var toolsContent: some View {
        let item: RootView.NavigationItem = selectedNavItem
        switch item {
        case .askAI: ChatView()
        case .logs: LogsMenuRootView()
        case .settings: SettingsView()
        default: EmptyView()
        }
    }

    @ViewBuilder
    private var attendanceContent: some View {
        if isIPhoneCompact {
            AttendanceStandaloneView()
        } else {
            TodayView(context: viewContext)
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

#if os(iOS)
/// Adaptive tabs that show a tab bar on iPhone and a sidebar on iPad.
/// Uses `.sidebarAdaptable` so iPad users can toggle between tab bar and sidebar.
struct RootAdaptiveTabs: View {
    @Binding var selectedNavItem: RootView.NavigationItem

    var body: some View {
        TabView(selection: $selectedNavItem) {
            // Top-level tabs (visible in tab bar on iPhone)
            Tab("Today", systemImage: "sun.max", value: .today) {
                RootDetailContent(selectedNavItem: .today)
            }

            Tab("Students", systemImage: "person.3", value: .students) {
                RootDetailContent(selectedNavItem: .students)
            }

            Tab("Attendance", systemImage: "checklist", value: .attendance) {
                RootDetailContent(selectedNavItem: .attendance)
            }

            Tab("Community", systemImage: "bubble.left.and.bubble.right", value: .community) {
                RootDetailContent(selectedNavItem: .community)
            }

            secondaryTabs
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    @TabContentBuilder<RootView.NavigationItem>
    private var secondaryTabs: some TabContent<RootView.NavigationItem> {
        // Sections (shown in sidebar on iPad, accessible via More on iPhone)
        TabSection {
            Tab(value: RootView.NavigationItem.todos) {
                RootDetailContent(selectedNavItem: .todos)
            } label: {
                Label("Todos", systemImage: "checkmark.circle")
            }
            Tab(value: RootView.NavigationItem.fridayReview) {
                RootDetailContent(selectedNavItem: .fridayReview)
            } label: {
                Label("Friday Review", systemImage: "checkmark.seal")
            }
        } header: {
            Text("Today")
        }

        TabSection {
Tab(value: RootView.NavigationItem.meetings) {
                RootDetailContent(selectedNavItem: .meetings)
            } label: {
                Label("Meetings", systemImage: "person.2")
            }
            Tab(value: RootView.NavigationItem.goingOut) {
                RootDetailContent(selectedNavItem: .goingOut)
            } label: {
                Label("Going Out", systemImage: "figure.walk")
            }
            Tab(value: RootView.NavigationItem.parentCommunication) {
                RootDetailContent(selectedNavItem: .parentCommunication)
            } label: {
                Label("Parent Comms", systemImage: "envelope")
            }
        } header: {
            Text("Students")
        }

        TabSection {
            Tab(value: RootView.NavigationItem.classroomJobs) {
                RootDetailContent(selectedNavItem: .classroomJobs)
            } label: {
                Label("Jobs", systemImage: "person.2.badge.gearshape")
            }
            Tab(value: RootView.NavigationItem.workCycle) {
                RootDetailContent(selectedNavItem: .workCycle)
            } label: {
                Label("Work Cycle", systemImage: "timer")
            }
            Tab(value: RootView.NavigationItem.prepChecklist) {
                RootDetailContent(selectedNavItem: .prepChecklist)
            } label: {
                Label("Prep Checklist", systemImage: "checklist.checked")
            }
        } header: {
            Text("Classroom")
        }

        TabSection {
            Tab(value: RootView.NavigationItem.lessons) {
                RootDetailContent(selectedNavItem: .lessons)
            } label: {
                Label("Lessons", systemImage: "book")
            }
            Tab(value: RootView.NavigationItem.planningChecklist) {
                RootDetailContent(selectedNavItem: .planningChecklist)
            } label: {
                Label("Checklist", systemImage: "list.clipboard")
            }
            Tab(value: RootView.NavigationItem.planningAgenda) {
                RootDetailContent(selectedNavItem: .planningAgenda)
            } label: {
                Label("Presentations", systemImage: "calendar")
            }
            Tab(value: RootView.NavigationItem.planningWork) {
                RootDetailContent(selectedNavItem: .planningWork)
            } label: {
                Label("Open Work", systemImage: "tray.full")
            }
Tab(value: RootView.NavigationItem.needsLesson) {
                RootDetailContent(selectedNavItem: .needsLesson)
            } label: {
                Label("Needs Lesson", systemImage: "clock.badge.exclamationmark")
            }
            Tab(value: RootView.NavigationItem.smallGroupPlanner) {
                RootDetailContent(selectedNavItem: .smallGroupPlanner)
            } label: {
                Label("Group Planner", systemImage: "person.3.sequence")
            }
            Tab(value: RootView.NavigationItem.planningProjects) {
                RootDetailContent(selectedNavItem: .planningProjects)
            } label: {
                Label("Projects", systemImage: "folder")
            }
        } header: {
            Text("Curriculum")
        }

        TabSection {
            Tab(value: RootView.NavigationItem.planningProgression) {
                RootDetailContent(selectedNavItem: .planningProgression)
            } label: {
                Label("Progression", systemImage: "chart.line.uptrend.xyaxis")
            }
            Tab(value: RootView.NavigationItem.progressDashboard) {
                RootDetailContent(selectedNavItem: .progressDashboard)
            } label: {
                Label("Progress Dashboard", systemImage: "person.text.rectangle")
            }
            Tab(value: RootView.NavigationItem.lessonFrequency) {
                RootDetailContent(selectedNavItem: .lessonFrequency)
            } label: {
                Label("Lesson Frequency", systemImage: SFSymbol.Chart.chartBar)
            }
            Tab(value: RootView.NavigationItem.curriculumBalance) {
                RootDetailContent(selectedNavItem: .curriculumBalance)
            } label: {
                Label("Curriculum Balance", systemImage: SFSymbol.Chart.chartPie)
            }
            Tab(value: RootView.NavigationItem.greatLessonsTimeline) {
                RootDetailContent(selectedNavItem: .greatLessonsTimeline)
            } label: {
                Label("Great Lessons", systemImage: "sparkles")
            }
            Tab(value: RootView.NavigationItem.transitionPlanner) {
                RootDetailContent(selectedNavItem: .transitionPlanner)
            } label: {
                Label("Transitions", systemImage: "arrow.right.arrow.left")
            }
            Tab(value: RootView.NavigationItem.threeYearCycle) {
                RootDetailContent(selectedNavItem: .threeYearCycle)
            } label: {
                Label("Three-Year Cycle", systemImage: "chart.bar.doc.horizontal")
            }
        } header: {
            Text("Progress")
        }

        TabSection {
            Tab(value: RootView.NavigationItem.resourceLibrary) {
                RootDetailContent(selectedNavItem: .resourceLibrary)
            } label: {
                Label("Resources", systemImage: "tray.2")
            }
            Tab(value: RootView.NavigationItem.supplies) {
                RootDetailContent(selectedNavItem: .supplies)
            } label: {
                Label("Supplies", systemImage: "shippingbox")
            }
            Tab(value: RootView.NavigationItem.procedures) {
                RootDetailContent(selectedNavItem: .procedures)
            } label: {
                Label("Procedures", systemImage: "doc.text")
            }
            Tab(value: RootView.NavigationItem.schedules) {
                RootDetailContent(selectedNavItem: .schedules)
            } label: {
                Label("Schedules", systemImage: "clock.badge.checkmark")
            }
            Tab(value: RootView.NavigationItem.perpetualCalendar) {
                RootDetailContent(selectedNavItem: .perpetualCalendar)
            } label: {
                Label("Calendar", systemImage: "calendar.day.timeline.leading")
            }
            Tab(value: RootView.NavigationItem.issues) {
                RootDetailContent(selectedNavItem: .issues)
            } label: {
                Label("Issues", systemImage: "exclamationmark.triangle")
            }
        } header: {
            Text("Resources")
        }

        TabSection {
            Tab(value: RootView.NavigationItem.askAI) {
                RootDetailContent(selectedNavItem: .askAI)
            } label: {
                Label("Ask AI", systemImage: "bubble.left.and.text.bubble.right")
            }
        } header: {
            Text("Tools")
        }

        TabSection {
            Tab(value: RootView.NavigationItem.logs) {
                RootDetailContent(selectedNavItem: .logs)
            } label: {
                Label("Logs", systemImage: "list.bullet")
            }
            Tab(value: RootView.NavigationItem.settings) {
                RootDetailContent(selectedNavItem: .settings)
            } label: {
                Label("Settings", systemImage: "gear")
            }
        } header: {
            Text("System")
        }
    }
}
#endif

/// More menu view for iPhone that shows additional navigation items
struct MoreMenuView: View {
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section("Daily") {
                    moreMenuButton(.meetings)
                    moreMenuButton(.goingOut)
                    moreMenuButton(.parentCommunication)
                    moreMenuButton(.classroomJobs)
                    moreMenuButton(.prepChecklist)
                    moreMenuButton(.fridayReview)
                    moreMenuButton(.workCycle)
                }

                Section("Planning") {
                    moreMenuButton(.lessons)
                    moreMenuButton(.planningChecklist)
                    moreMenuButton(.planningAgenda)
                    moreMenuButton(.planningWork)
                    moreMenuButton(.planningProgression)
                    moreMenuButton(.planningProjects)
                    moreMenuButton(.lessonFrequency)
                    moreMenuButton(.curriculumBalance)
                    moreMenuButton(.greatLessonsTimeline)
                    moreMenuButton(.transitionPlanner)
                    moreMenuButton(.threeYearCycle)
                    moreMenuButton(.needsLesson)
                    moreMenuButton(.smallGroupPlanner)
                }

                Section("Resources") {
                    moreMenuButton(.resourceLibrary)
                    moreMenuButton(.supplies)
                    moreMenuButton(.procedures)
                    moreMenuButton(.schedules)
                    moreMenuButton(.perpetualCalendar)
                    moreMenuButton(.issues)
                }

                Section("AI") {
                    moreMenuButton(.askAI)
                }

                Section("System") {
                    moreMenuButton(.logs)
                    moreMenuButton(.settings)
                }
            }
            .navigationTitle("More")
            .navigationDestination(for: RootView.NavigationItem.self) { item in
                RootDetailContent(selectedNavItem: item)
            }
        }
    }

    private func moreMenuButton(_ item: RootView.NavigationItem) -> some View {
        Button {
            navigationPath.append(item)
        } label: {
            Label(item.displayName, systemImage: item.icon)
        }
        .buttonStyle(.plain)
    }
}
