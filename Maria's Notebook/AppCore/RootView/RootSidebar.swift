// RootSidebar.swift
// Sidebar navigation for RootView - extracted for maintainability

import SwiftUI
import SwiftData

/// Sidebar with grouped sections (Source List style) for selecting navigation items.
struct RootSidebar: View {
    @Binding var selection: RootView.NavigationItem

    var body: some View {
        #if os(macOS)
        macOSSidebar
        #else
        iOSSidebar
        #endif
    }

    #if os(macOS)
    private var macOSSidebar: some View {
        List(selection: $selection) {
            Section("Classroom") {
                NavigationLink(value: RootView.NavigationItem.today) {
                    Label("Today", systemImage: "sun.max")
                }
                NavigationLink(value: RootView.NavigationItem.students) {
                    Label("Students", systemImage: "person.3")
                }
                NavigationLink(value: RootView.NavigationItem.community) {
                    Label("Community", systemImage: "bubble.left.and.bubble.right")
                }
            }

            Section("Curriculum") {
                NavigationLink(value: RootView.NavigationItem.lessons) {
                    Label("Lessons", systemImage: "book")
                }
                NavigationLink(value: RootView.NavigationItem.planningChecklist) {
                    Label("Checklist", systemImage: "list.clipboard")
                }
                NavigationLink(value: RootView.NavigationItem.planningAgenda) {
                    Label("Presentations", systemImage: "calendar")
                }
                NavigationLink(value: RootView.NavigationItem.planningWork) {
                    Label("Open Work", systemImage: "tray.full")
                }
                NavigationLink(value: RootView.NavigationItem.planningProjects) {
                    Label("Projects", systemImage: "folder")
                }
            }

            Section("System") {
                NavigationLink(value: RootView.NavigationItem.logs) {
                    Label("Logs", systemImage: "list.bullet")
                }
                NavigationLink(value: RootView.NavigationItem.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .listStyle(.sidebar)
    }
    #endif

    private var iOSSidebar: some View {
        List {
            Section("Classroom") {
                Button { selection = .today } label: {
                    Label("Today", systemImage: "sun.max")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View today's schedule, reminders, and tasks")

                Button { selection = .students } label: {
                    Label("Students", systemImage: "person.3")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage student profiles and records")

                Button { selection = .community } label: {
                    Label("Community", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View community meetings and topics")
            }

            Section("Curriculum") {
                Button { selection = .lessons } label: {
                    Label("Lessons", systemImage: "book")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Browse and manage lesson plans")

                Button { selection = .planningChecklist } label: {
                    Label("Checklist", systemImage: "list.clipboard")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View class subject checklist")

                Button { selection = .planningAgenda } label: {
                    Label("Presentations", systemImage: "calendar")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage lesson presentations agenda")

                Button { selection = .planningWork } label: {
                    Label("Open Work", systemImage: "tray.full")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View and manage student work")

                Button { selection = .planningProjects } label: {
                    Label("Projects", systemImage: "folder")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage student projects")
            }

            Section("System") {
                Button { selection = .logs } label: {
                    Label("Logs", systemImage: "list.bullet")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View activity and observation logs")

                Button { selection = .settings } label: {
                    Label("Settings", systemImage: "gear")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Configure app preferences and sync options")
            }
        }
    }
}
