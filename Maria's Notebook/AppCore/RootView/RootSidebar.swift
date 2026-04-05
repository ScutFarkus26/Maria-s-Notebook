// RootSidebar.swift
// Sidebar navigation for RootView - extracted for maintainability

import SwiftUI
import CoreData

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
}

// MARK: - Platform Sidebars

extension RootSidebar {
    #if os(macOS)
    var macOSSidebar: some View {
        List(selection: $selection) {
            Section("Today") {
                sidebarRow(.today, title: "Today", systemImage: SFSymbol.Weather.sun)

                sidebarRow(.todos, title: "Todos", systemImage: SFSymbol.Action.checkmarkCircle)
            }

            Section("Students") {
                sidebarRow(.students, title: "Students", systemImage: SFSymbol.People.person3)
                .contextMenu {
                    Button {
                        appRouter.requestNewStudent()
                    } label: {
                        Label("New CDStudent", systemImage: "person.badge.plus")
                    }

                    Button {
                        appRouter.requestImportStudents()
                    } label: {
                        Label("Import Students…", systemImage: "square.and.arrow.down")
                    }
                }

                sidebarRow(.meetings, title: "Meetings", systemImage: SFSymbol.People.person2)

                sidebarRow(.goingOut, title: "Going Out", systemImage: "figure.walk")

            }

            Section("Classroom") {
                sidebarRow(.community, title: "Community", systemImage: "bubble.left.and.bubble.right")

                sidebarRow(.classroomJobs, title: "Jobs", systemImage: "person.2.badge.gearshape")

                sidebarRow(.attendance, title: "Attendance", systemImage: "checklist")
            }

            Section("Curriculum") {
                sidebarRow(.lessons, title: "Lessons", systemImage: SFSymbol.Education.book)
                .contextMenu {
                    Button {
                        appRouter.requestNewLesson()
                    } label: {
                        Label("New CDLesson", systemImage: SFSymbol.Action.plusCircle)
                    }

                    Button {
                        appRouter.requestImportLessons()
                    } label: {
                        Label("Import Lessons…", systemImage: "square.and.arrow.down")
                    }
                }

                sidebarRow(.planningChecklist, title: "Checklist", systemImage: "list.clipboard")

                sidebarRow(.planningAgenda, title: "Presentations", systemImage: SFSymbol.Time.calendar)

                sidebarRow(.planningWork, title: "Open Work", systemImage: "tray.full")
                .contextMenu {
                    Button {
                        appRouter.requestNewWork()
                    } label: {
                        Label("New Work…", systemImage: SFSymbol.Action.plusCircle)
                    }
                }

                sidebarRow(.needsLesson, title: "Needs Lesson", systemImage: "clock.badge.exclamationmark")

                sidebarRow(.planningProjects, title: "Projects", systemImage: SFSymbol.CDDocument.folder)
            }

            Section("Progress") {
                sidebarRow(.planningProgression, title: "Progression", systemImage: SFSymbol.Chart.chartLine)

                sidebarRow(.progressDashboard, title: "Progress Dashboard", systemImage: "person.text.rectangle")

                sidebarRow(.lessonFrequency, title: "Lesson Frequency", systemImage: SFSymbol.Chart.chartBar)

                sidebarRow(.curriculumBalance, title: "Curriculum Balance", systemImage: SFSymbol.Chart.chartPie)

                sidebarRow(.transitionPlanner, title: "Transitions", systemImage: "arrow.right.arrow.left")
            }

            Section("Resources") {
                sidebarRow(.resourceLibrary, title: "Resources", systemImage: "tray.2")

                sidebarRow(.supplies, title: "Supplies", systemImage: "shippingbox")

                sidebarRow(.procedures, title: "Procedures", systemImage: SFSymbol.CDDocument.docText)

                sidebarRow(.schedules, title: "Schedules", systemImage: "clock.badge.checkmark")

                sidebarRow(.perpetualCalendar, title: "Calendar", systemImage: "calendar.day.timeline.leading")

                sidebarRow(.issues, title: "Issues", systemImage: "exclamationmark.triangle")
            }

            Section("Tools") {
                sidebarRow(.askAI, title: "Ask AI", systemImage: "bubble.left.and.text.bubble.right")
            }

            Section("System") {
                sidebarRow(.logs, title: "Logs", systemImage: SFSymbol.List.list)
                sidebarRow(.settings, title: "Settings", systemImage: SFSymbol.Settings.gear)
            }
        }
        .listStyle(.sidebar)
    }
    #endif

    #if os(macOS)
    private func sidebarRow(_ item: RootView.NavigationItem, title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .contentShape(Rectangle())
            .tag(item)
    }
    #endif

    var iOSSidebar: some View {
        List {
            Section("Today") {
                Button { selection = .today } label: {
                    Label("Today", systemImage: SFSymbol.Weather.sun)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View today's schedule, reminders, and tasks")

                Button { selection = .todos } label: {
                    Label("Todos", systemImage: SFSymbol.Action.checkmarkCircle)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage your personal todos and tasks")
            }

            Section("Students") {
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

                Button { selection = .goingOut } label: {
                    Label("Going Out", systemImage: "figure.walk")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Plan and track student going-out excursions")

            }

            Section("Classroom") {
                Button { selection = .community } label: {
                    Label("Community", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View community meetings and topics")

                Button { selection = .classroomJobs } label: {
                    Label("Jobs", systemImage: "person.2.badge.gearshape")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage classroom job rotation board")

                Button { selection = .attendance } label: {
                    Label("Attendance", systemImage: "checklist")
                }
                .buttonStyle(.plain)
                .accessibilityHint("CDTrackEntity daily student attendance")
            }

            Section("Curriculum") {
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

                Button { selection = .needsLesson } label: {
                    Label("Needs Lesson", systemImage: "clock.badge.exclamationmark")
                }
                .buttonStyle(.plain)
                .accessibilityHint("See which students need a lesson based on days since last presentation")

                Button { selection = .planningProjects } label: {
                    Label("Projects", systemImage: SFSymbol.CDDocument.folder)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Manage student projects")
            }

            Section("Progress") {
                Button { selection = .planningProgression } label: {
                    Label("Progression", systemImage: SFSymbol.Chart.chartLine)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View student progression through curriculum")

                Button { selection = .progressDashboard } label: {
                    Label("Progress Dashboard", systemImage: "person.text.rectangle")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View per-student progress across all subjects")

                Button { selection = .lessonFrequency } label: {
                    Label("Lesson Frequency", systemImage: SFSymbol.Chart.chartBar)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View weekly lesson frequency per student")

                Button { selection = .curriculumBalance } label: {
                    Label("Curriculum Balance", systemImage: SFSymbol.Chart.chartPie)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Analyze subject distribution and curriculum gaps")

                Button { selection = .transitionPlanner } label: {
                    Label("Transitions", systemImage: "arrow.right.arrow.left")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Plan and track student transitions between levels")
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
                .accessibilityHint("CDTrackEntity classroom supplies and inventory")

                Button { selection = .procedures } label: {
                    Label("Procedures", systemImage: SFSymbol.CDDocument.docText)
                }
                .buttonStyle(.plain)
                .accessibilityHint("View classroom procedures and routines")

                Button { selection = .schedules } label: {
                    Label("Schedules", systemImage: "clock.badge.checkmark")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View recurring schedules")

                Button { selection = .perpetualCalendar } label: {
                    Label("Calendar", systemImage: "calendar.day.timeline.leading")
                }
                .buttonStyle(.plain)
                .accessibilityHint("View perpetual year-at-a-glance calendar")

                Button { selection = .issues } label: {
                    Label("Issues", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.plain)
                .accessibilityHint("CDTrackEntity and resolve classroom issues")
            }

            Section("Tools") {
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
