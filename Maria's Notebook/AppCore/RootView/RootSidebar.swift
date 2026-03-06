// RootSidebar.swift
// Sidebar navigation for RootView - extracted for maintainability

import SwiftUI
import SwiftData

/// Sidebar with grouped sections (Source List style) for selecting navigation items.
struct RootSidebar: View {
    @Binding var selection: RootView.NavigationItem
    @Environment(\.appRouter) private var appRouter

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
            Section("Daily") {
                NavigationLink(value: RootView.NavigationItem.today) {
                    Label("Today", systemImage: SFSymbol.Weather.sun)
                }

                NavigationLink(value: RootView.NavigationItem.students) {
                    Label("Students", systemImage: SFSymbol.People.person3)
                }
                .contextMenu {
                    Button {
                        appRouter.requestNewStudent()
                    } label: {
                        Label("New Student", systemImage: "person.badge.plus")
                    }

                    Button {
                        appRouter.requestImportStudents()
                    } label: {
                        Label("Import Students…", systemImage: "square.and.arrow.down")
                    }
                }

                NavigationLink(value: RootView.NavigationItem.meetings) {
                    Label("Meetings", systemImage: SFSymbol.People.person2)
                }

                NavigationLink(value: RootView.NavigationItem.community) {
                    Label("Community", systemImage: "bubble.left.and.bubble.right")
                }
            }

            Section("Planning") {
                NavigationLink(value: RootView.NavigationItem.todos) {
                    Label("Todos", systemImage: SFSymbol.Action.checkmarkCircle)
                }

                NavigationLink(value: RootView.NavigationItem.lessons) {
                    Label("Lessons", systemImage: SFSymbol.Education.book)
                }
                .contextMenu {
                    Button {
                        appRouter.requestNewLesson()
                    } label: {
                        Label("New Lesson", systemImage: SFSymbol.Action.plusCircle)
                    }

                    Button {
                        appRouter.requestImportLessons()
                    } label: {
                        Label("Import Lessons…", systemImage: "square.and.arrow.down")
                    }
                }

                NavigationLink(value: RootView.NavigationItem.planningChecklist) {
                    Label("Checklist", systemImage: "list.clipboard")
                }

                NavigationLink(value: RootView.NavigationItem.planningAgenda) {
                    Label("Presentations", systemImage: SFSymbol.Time.calendar)
                }

                NavigationLink(value: RootView.NavigationItem.planningWork) {
                    Label("Open Work", systemImage: "tray.full")
                }
                .contextMenu {
                    Button {
                        appRouter.requestNewWork()
                    } label: {
                        Label("New Work…", systemImage: SFSymbol.Action.plusCircle)
                    }
                }

                NavigationLink(value: RootView.NavigationItem.planningProgression) {
                    Label("Progression", systemImage: SFSymbol.Chart.chartLine)
                }

                NavigationLink(value: RootView.NavigationItem.planningProjects) {
                    Label("Projects", systemImage: SFSymbol.Document.folder)
                }
            }

            Section("Resources") {
                NavigationLink(value: RootView.NavigationItem.resourceLibrary) {
                    Label("Resources", systemImage: "tray.2")
                }

                NavigationLink(value: RootView.NavigationItem.supplies) {
                    Label("Supplies", systemImage: "shippingbox")
                }

                NavigationLink(value: RootView.NavigationItem.procedures) {
                    Label("Procedures", systemImage: SFSymbol.Document.docText)
                }

                NavigationLink(value: RootView.NavigationItem.schedules) {
                    Label("Schedules", systemImage: "clock.badge.checkmark")
                }

                NavigationLink(value: RootView.NavigationItem.issues) {
                    Label("Issues", systemImage: "exclamationmark.triangle")
                }
            }

            Section("AI") {
                NavigationLink(value: RootView.NavigationItem.askAI) {
                    Label("Ask AI", systemImage: "bubble.left.and.text.bubble.right")
                }
            }

            Section("System") {
                NavigationLink(value: RootView.NavigationItem.logs) {
                    Label("Logs", systemImage: SFSymbol.List.list)
                }
                NavigationLink(value: RootView.NavigationItem.settings) {
                    Label("Settings", systemImage: SFSymbol.Settings.gear)
                }
            }
        }
        .listStyle(.sidebar)
    }
    #endif

    private var iOSSidebar: some View {
        List {
            Section("Daily") {
                Button { selection = .today } label: {
                    Label("Today", systemImage: SFSymbol.Weather.sun)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View today's schedule, reminders, and tasks")

                Button { selection = .students } label: {
                    Label("Students", systemImage: SFSymbol.People.person3)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage student profiles and records")

                Button { selection = .meetings } label: {
                    Label("Meetings", systemImage: SFSymbol.People.person2)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Conduct weekly student meetings")

                Button { selection = .community } label: {
                    Label("Community", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View community meetings and topics")
            }

            Section("Planning") {
                Button { selection = .todos } label: {
                    Label("Todos", systemImage: SFSymbol.Action.checkmarkCircle)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage your personal todos and tasks")

                Button { selection = .lessons } label: {
                    Label("Lessons", systemImage: SFSymbol.Education.book)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Browse and manage lesson plans")

                Button { selection = .planningChecklist } label: {
                    Label("Checklist", systemImage: "list.clipboard")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View class subject checklist")

                Button { selection = .planningAgenda } label: {
                    Label("Presentations", systemImage: SFSymbol.Time.calendar)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage lesson presentations agenda")

                Button { selection = .planningWork } label: {
                    Label("Open Work", systemImage: "tray.full")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View and manage student work")

                Button { selection = .planningProgression } label: {
                    Label("Progression", systemImage: SFSymbol.Chart.chartLine)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View student progression through curriculum")

                Button { selection = .planningProjects } label: {
                    Label("Projects", systemImage: SFSymbol.Document.folder)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage student projects")
            }

            Section("Resources") {
                Button { selection = .resourceLibrary } label: {
                    Label("Resources", systemImage: "tray.2")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Browse and organize classroom resource documents")

                Button { selection = .supplies } label: {
                    Label("Supplies", systemImage: "shippingbox")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Track classroom supplies and inventory")

                Button { selection = .procedures } label: {
                    Label("Procedures", systemImage: SFSymbol.Document.docText)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View classroom procedures and routines")

                Button { selection = .schedules } label: {
                    Label("Schedules", systemImage: "clock.badge.checkmark")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View recurring schedules")

                Button { selection = .issues } label: {
                    Label("Issues", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Track and resolve classroom issues")
            }

            Section("AI") {
                Button { selection = .askAI } label: {
                    Label("Ask AI", systemImage: "bubble.left.and.text.bubble.right")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ask questions about your classroom data")
            }

            Section("System") {
                Button { selection = .logs } label: {
                    Label("Logs", systemImage: SFSymbol.List.list)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View activity and observation logs")

                Button { selection = .settings } label: {
                    Label("Settings", systemImage: SFSymbol.Settings.gear)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Configure app preferences and sync options")
            }
        }
    }
}
