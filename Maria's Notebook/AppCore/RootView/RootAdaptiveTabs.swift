// RootAdaptiveTabs.swift
// iOS-only adaptive tabs (iPhone tab bar / iPad sidebar) - extracted from RootDetailContent.

#if os(iOS)
import SwiftUI

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
        // Sections (shown in sidebar on iPad, accessible via More on iPhone).
        // Today / Students / Attendance / Community are primary tabs above and intentionally
        // omitted from these sections to avoid duplicate listings.
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
            Tab(value: RootView.NavigationItem.smallSequencePlanner) {
                RootDetailContent(selectedNavItem: .smallSequencePlanner)
            } label: {
                Label("Group Planner", systemImage: "person.3.sequence")
            }
            Tab(value: RootView.NavigationItem.planningChecklist) {
                RootDetailContent(selectedNavItem: .planningChecklist)
            } label: {
                Label("Checklist", systemImage: "list.clipboard")
            }
        } header: {
            Text("Planning")
        }

        TabSection {
            Tab(value: RootView.NavigationItem.lessons) {
                RootDetailContent(selectedNavItem: .lessons)
            } label: {
                Label("Lessons", systemImage: "book")
            }
            Tab(value: RootView.NavigationItem.stories) {
                RootDetailContent(selectedNavItem: .stories)
            } label: {
                Label("Stories", systemImage: "books.vertical")
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
            Tab(value: RootView.NavigationItem.thisWeeksParsha) {
                RootDetailContent(selectedNavItem: .thisWeeksParsha)
            } label: {
                Label("This Week’s Parsha", systemImage: "book.closed")
            }
            Tab(value: RootView.NavigationItem.parshaCalendar) {
                RootDetailContent(selectedNavItem: .parshaCalendar)
            } label: {
                Label("Parsha Calendar", systemImage: "calendar")
            }
        } header: {
            Text("Parsha")
        }

        TabSection {
            Tab(value: RootView.NavigationItem.progressDashboard) {
                RootDetailContent(selectedNavItem: .progressDashboard)
            } label: {
                Label("Progress Dashboard", systemImage: "person.text.rectangle")
            }
        } header: {
            Text("Insights")
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
        } header: {
            Text("Resources")
        }

        TabSection {
            Tab(value: RootView.NavigationItem.askAI) {
                RootDetailContent(selectedNavItem: .askAI)
            } label: {
                Label("Ask AI", systemImage: "bubble.left.and.text.bubble.right")
            }
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
