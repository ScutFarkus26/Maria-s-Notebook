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

    var body: some View {
        Group {
            switch selectedNavItem {
            case .today:
                TodayView(context: modelContext)
            case .attendance:
                TodayView(context: modelContext)
            case .note:
                noteTabContent
            case .students:
                StudentsRootView()
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
            case .planningProjects:
                ProjectsRootView()
            case .community:
                CommunityMeetingsView()
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
                Section("Classroom") {
                    moreMenuButton(.lessons)
                    moreMenuButton(.community)
                    moreMenuButton(.logs)
                }

                Section("Planning") {
                    moreMenuButton(.planningChecklist)
                    moreMenuButton(.planningAgenda)
                    moreMenuButton(.planningWork)
                    moreMenuButton(.planningProjects)
                }

                Section("System") {
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
