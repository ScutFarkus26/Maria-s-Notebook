// RootDetailContent.swift
// Detail content routing for RootView - extracted for maintainability

import SwiftUI
import SwiftData

/// Extracted detail content for RootView. Routes based on NavigationItem selection.
struct RootDetailContent: View {
    let selectedNavItem: RootView.NavigationItem
    @Environment(\.modelContext) private var modelContext
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
                TodayView(context: modelContext)
            case .attendance:
                // On iPhone compact, use standalone attendance view
                if isIPhoneCompact {
                    AttendanceStandaloneView()
                } else {
                    TodayView(context: modelContext)
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
            case .cosmicMap:
                CosmicMapRootView()
            case .observationMode:
                ObservationModeView()
            case .goingOut:
                GoingOutRootView()
            case .threePeriod:
                ThreePeriodRootView()
            case .classroomJobs:
                ClassroomJobsRootView()
            case .transitionPlanner:
                TransitionPlannerRootView()
            case .needsLesson:
                NeedsLessonView()
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

            // Sections (shown in sidebar on iPad, accessible via More on iPhone)
            TabSection("Today") {
                Tab("Todos", systemImage: "checkmark.circle", value: .todos) {
                    RootDetailContent(selectedNavItem: .todos)
                }
            }

            TabSection("Students") {
                Tab("Observe", systemImage: "eye", value: .observationMode) {
                    RootDetailContent(selectedNavItem: .observationMode)
                }
                Tab("Meetings", systemImage: "person.2", value: .meetings) {
                    RootDetailContent(selectedNavItem: .meetings)
                }
                Tab("Going Out", systemImage: "figure.walk", value: .goingOut) {
                    RootDetailContent(selectedNavItem: .goingOut)
                }
                Tab("Three-Period", systemImage: "3.circle", value: .threePeriod) {
                    RootDetailContent(selectedNavItem: .threePeriod)
                }
            }

            TabSection("Classroom") {
                Tab("Jobs", systemImage: "person.2.badge.gearshape", value: .classroomJobs) {
                    RootDetailContent(selectedNavItem: .classroomJobs)
                }
            }

            TabSection("Curriculum") {
                Tab("Lessons", systemImage: "book", value: .lessons) {
                    RootDetailContent(selectedNavItem: .lessons)
                }
                Tab("Checklist", systemImage: "list.clipboard", value: .planningChecklist) {
                    RootDetailContent(selectedNavItem: .planningChecklist)
                }
                Tab("Presentations", systemImage: "calendar", value: .planningAgenda) {
                    RootDetailContent(selectedNavItem: .planningAgenda)
                }
                Tab("Open Work", systemImage: "tray.full", value: .planningWork) {
                    RootDetailContent(selectedNavItem: .planningWork)
                }
                Tab("Cosmic Map", systemImage: "globe.americas", value: .cosmicMap) {
                    RootDetailContent(selectedNavItem: .cosmicMap)
                }
                Tab("Needs Lesson", systemImage: "clock.badge.exclamationmark", value: .needsLesson) {
                    RootDetailContent(selectedNavItem: .needsLesson)
                }
                Tab("Projects", systemImage: "folder", value: .planningProjects) {
                    RootDetailContent(selectedNavItem: .planningProjects)
                }
            }

            TabSection("Progress") {
                Tab("Progression", systemImage: "chart.line.uptrend.xyaxis", value: .planningProgression) {
                    RootDetailContent(selectedNavItem: .planningProgression)
                }
                Tab("Progress Dashboard", systemImage: "person.text.rectangle", value: .progressDashboard) {
                    RootDetailContent(selectedNavItem: .progressDashboard)
                }
                Tab("Lesson Frequency", systemImage: SFSymbol.Chart.chartBar, value: .lessonFrequency) {
                    RootDetailContent(selectedNavItem: .lessonFrequency)
                }
                Tab("Curriculum Balance", systemImage: SFSymbol.Chart.chartPie, value: .curriculumBalance) {
                    RootDetailContent(selectedNavItem: .curriculumBalance)
                }
                Tab("Transitions", systemImage: "arrow.right.arrow.left", value: .transitionPlanner) {
                    RootDetailContent(selectedNavItem: .transitionPlanner)
                }
            }

            TabSection("Resources") {
                Tab("Resources", systemImage: "tray.2", value: .resourceLibrary) {
                    RootDetailContent(selectedNavItem: .resourceLibrary)
                }
                Tab("Supplies", systemImage: "shippingbox", value: .supplies) {
                    RootDetailContent(selectedNavItem: .supplies)
                }
                Tab("Procedures", systemImage: "doc.text", value: .procedures) {
                    RootDetailContent(selectedNavItem: .procedures)
                }
                Tab("Schedules", systemImage: "clock.badge.checkmark", value: .schedules) {
                    RootDetailContent(selectedNavItem: .schedules)
                }
                Tab("Issues", systemImage: "exclamationmark.triangle", value: .issues) {
                    RootDetailContent(selectedNavItem: .issues)
                }
            }

            TabSection("Tools") {
                Tab("Ask AI", systemImage: "bubble.left.and.text.bubble.right", value: .askAI) {
                    RootDetailContent(selectedNavItem: .askAI)
                }
            }

            TabSection("System") {
                Tab("Logs", systemImage: "list.bullet", value: .logs) {
                    RootDetailContent(selectedNavItem: .logs)
                }
                Tab("Settings", systemImage: "gear", value: .settings) {
                    RootDetailContent(selectedNavItem: .settings)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
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
                    moreMenuButton(.observationMode)
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
                    moreMenuButton(.cosmicMap)
                    moreMenuButton(.threePeriod)
                    moreMenuButton(.transitionPlanner)
                    moreMenuButton(.needsLesson)
                }

                Section("Resources") {
                    moreMenuButton(.resourceLibrary)
                    moreMenuButton(.supplies)
                    moreMenuButton(.procedures)
                    moreMenuButton(.schedules)
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
