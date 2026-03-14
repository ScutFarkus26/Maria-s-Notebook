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

/// Compact iPhone tabs using a standard TabView with grouped navigation items.
struct RootCompactTabs: View {
    @Binding var selectedNavItem: RootView.NavigationItem

    private var mainTabs: [RootView.NavigationItem] {
        [.attendance, .today, .students, .community]
    }

    var body: some View {
        TabView(selection: Binding(
            get: { selectedNavItem.rawValue },
            set: { if let item = RootView.NavigationItem(rawValue: $0) { selectedNavItem = item } }
        )) {
            ForEach(mainTabs) { item in
                RootDetailContent(selectedNavItem: item)
                    .tabItem {
                        Label(item.displayName, systemImage: item.icon)
                    }
                    .tag(item.rawValue)
            }
        }
    }
}

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
