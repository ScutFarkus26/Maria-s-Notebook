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
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    var body: some View {
        Group {
            switch selectedNavItem {
            case .today:
                TodayView(context: viewContext)
            case .attendance:
                // On iPhone compact, use standalone attendance view
                if isIPhoneCompact {
                    AttendanceStandaloneView()
                } else {
                    TodayView(context: viewContext)
                }
            case .note:
                noteTabContent
            case .todos:
                TodoMainView()
            case .students:
                StudentsRootView()
            case .supplies:
                SuppliesListView()
            case .procedures:
                ProceduresListView()
            case .meetings:
                MeetingsWorkflowView()
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
            case .planningProgression:
                ProgressionRootView()
            case .planningProjects:
                ProjectsRootView()
            case .progressDashboard:
                ProgressDashboardView()
            case .lessonFrequency:
                LessonFrequencyView()
            case .curriculumBalance:
                CurriculumBalanceView()
            case .greatLessonsTimeline:
                GreatLessonsTimelineView()
            case .goingOut:
                GoingOutRootView()
            case .classroomJobs:
                ClassroomJobsRootView()
            case .transitionPlanner:
                TransitionPlannerRootView()
            case .needsLesson:
                NeedsLessonView()
            case .perpetualCalendar:
                PerpetualCalendarView()
            case .community:
                CommunityMeetingsView()
            case .schedules:
                SchedulesView()
            case .issues:
                IssuesListView()
            case .resourceLibrary:
                ResourceLibraryView()
            case .askAI:
                ChatView()
            case .logs:
                LogsMenuRootView()
            case .settings:
                SettingsView()
            }
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
        } header: {
            Text("Students")
        }

        TabSection {
            Tab(value: RootView.NavigationItem.classroomJobs) {
                RootDetailContent(selectedNavItem: .classroomJobs)
            } label: {
                Label("Jobs", systemImage: "person.2.badge.gearshape")
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
                    moreMenuButton(.classroomJobs)
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
                    moreMenuButton(.needsLesson)
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
