// MoreMenuView.swift
// More menu shown on iPhone for navigation items not in the primary tab bar.

import SwiftUI

/// More menu view for iPhone that shows additional navigation items
struct MoreMenuView: View {
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            List {
                Section("Today") {
                    moreMenuButton(.todos)
                }

                Section("Students") {
                    moreMenuButton(.meetings)
                    moreMenuButton(.goingOut)
                }

                Section("Curriculum") {
                    moreMenuButton(.lessons)
                    moreMenuButton(.stories)
                    moreMenuButton(.planningProjects)
                }

                Section("Planning") {
                    moreMenuButton(.planningAgenda)
                    moreMenuButton(.planningWork)
                    moreMenuButton(.needsLesson)
                    moreMenuButton(.smallSequencePlanner)
                    moreMenuButton(.planningChecklist)
                }

                Section("Insights") {
                    moreMenuButton(.progressDashboard)
                }

                Section("Resources") {
                    moreMenuButton(.resourceLibrary)
                    moreMenuButton(.supplies)
                    moreMenuButton(.procedures)
                    moreMenuButton(.schedules)
                    moreMenuButton(.perpetualCalendar)
                }

                Section("System") {
                    moreMenuButton(.askAI)
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
