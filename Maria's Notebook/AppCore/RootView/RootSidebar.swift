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

                sidebarRow(.fridayReview, title: "Friday Review", systemImage: "checkmark.seal")
            }

            Section("Students") {
                sidebarRow(.students, title: "Students", systemImage: SFSymbol.People.person3)
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

                sidebarRow(.meetings, title: "Meetings", systemImage: SFSymbol.People.person2)

                sidebarRow(.goingOut, title: "Going Out", systemImage: "figure.walk")

                sidebarRow(.parentCommunication, title: "Parent Comms", systemImage: "envelope")

            }

            Section("Classroom") {
                sidebarRow(.community, title: "Community", systemImage: "bubble.left.and.bubble.right")

                sidebarRow(.classroomJobs, title: "Jobs", systemImage: "person.2.badge.gearshape")

                sidebarRow(.attendance, title: "Attendance", systemImage: "checklist")

                sidebarRow(.workCycle, title: "Work Cycle", systemImage: "timer")

                sidebarRow(.prepChecklist, title: "Prep Checklist", systemImage: "checklist.checked")
            }

            Section("Curriculum") {
                sidebarRow(.lessons, title: "Lessons", systemImage: SFSymbol.Education.book)
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

                sidebarRow(.smallGroupPlanner, title: "Group Planner", systemImage: "person.3.sequence")

                sidebarRow(.planningProjects, title: "Projects", systemImage: SFSymbol.CDDocument.folder)
            }

            Section("Progress") {
                sidebarRow(.planningProgression, title: "Progression", systemImage: SFSymbol.Chart.chartLine)

                sidebarRow(.progressDashboard, title: "Progress Dashboard", systemImage: "person.text.rectangle")

                sidebarRow(.lessonFrequency, title: "Lesson Frequency", systemImage: SFSymbol.Chart.chartBar)

                sidebarRow(.curriculumBalance, title: "Curriculum Balance", systemImage: SFSymbol.Chart.chartPie)

                sidebarRow(.greatLessonsTimeline, title: "Great Lessons", systemImage: "sparkles")

                sidebarRow(.transitionPlanner, title: "Transitions", systemImage: "arrow.right.arrow.left")

                sidebarRow(.threeYearCycle, title: "Three-Year Cycle", systemImage: "chart.bar.doc.horizontal")
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
            iOSSidebarTodaySection
            iOSSidebarStudentsSection
            iOSSidebarClassroomSection
            iOSSidebarCurriculumSection
            iOSSidebarProgressSection
            iOSSidebarResourcesSection
            iOSSidebarToolsSection
            iOSSidebarSystemSection
        }
    }

    private func iOSSidebarButton(_ item: RootView.NavigationItem, title: String, systemImage: String, hint: String) -> some View {
        Button { selection = item } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    private var iOSSidebarTodaySection: some View {
        Section("Today") {
            iOSSidebarButton(.today, title: "Today", systemImage: SFSymbol.Weather.sun, hint: "View today's schedule, reminders, and tasks")
            iOSSidebarButton(.todos, title: "Todos", systemImage: SFSymbol.Action.checkmarkCircle, hint: "Manage your personal todos and tasks")
            iOSSidebarButton(.fridayReview, title: "Friday Review", systemImage: "checkmark.seal", hint: "Review the week and prepare Monday priorities")
        }
    }

    private var iOSSidebarStudentsSection: some View {
        Section("Students") {
            iOSSidebarButton(.students, title: "Students", systemImage: SFSymbol.People.person3, hint: "Manage student profiles and records")
            iOSSidebarButton(.meetings, title: "Meetings", systemImage: SFSymbol.People.person2, hint: "Conduct weekly student meetings")
            iOSSidebarButton(.goingOut, title: "Going Out", systemImage: "figure.walk", hint: "Plan and track student going-out excursions")
            iOSSidebarButton(.parentCommunication, title: "Parent Comms", systemImage: "envelope", hint: "Draft and track parent communications")
        }
    }

    private var iOSSidebarClassroomSection: some View {
        Section("Classroom") {
            iOSSidebarButton(.community, title: "Community", systemImage: "bubble.left.and.bubble.right", hint: "View community meetings and topics")
            iOSSidebarButton(.classroomJobs, title: "Jobs", systemImage: "person.2.badge.gearshape", hint: "Manage classroom job rotation board")
            iOSSidebarButton(.attendance, title: "Attendance", systemImage: "checklist", hint: "Track daily student attendance")
            iOSSidebarButton(.workCycle, title: "Work Cycle", systemImage: "timer", hint: "Track student activity during the work cycle")
            iOSSidebarButton(.prepChecklist, title: "Prep Checklist", systemImage: "checklist.checked", hint: "Daily classroom environment preparation checklist")
        }
    }

    private var iOSSidebarCurriculumSection: some View {
        Section("Curriculum") {
            iOSSidebarButton(.lessons, title: "Lessons", systemImage: SFSymbol.Education.book, hint: "Browse and manage lesson plans")
            iOSSidebarButton(.planningChecklist, title: "Checklist", systemImage: "list.clipboard", hint: "View class subject checklist")
            iOSSidebarButton(.planningAgenda, title: "Presentations", systemImage: SFSymbol.Time.calendar, hint: "Manage lesson presentations agenda")
            iOSSidebarButton(.planningWork, title: "Open Work", systemImage: "tray.full", hint: "View and manage student work")
            iOSSidebarButton(.needsLesson, title: "Needs Lesson", systemImage: "clock.badge.exclamationmark", hint: "See which students need a lesson based on days since last presentation")
            iOSSidebarButton(.smallGroupPlanner, title: "Group Planner", systemImage: "person.3.sequence", hint: "Find ready and almost-ready students for group presentations")
            iOSSidebarButton(.planningProjects, title: "Projects", systemImage: SFSymbol.CDDocument.folder, hint: "Manage student projects")
        }
    }

    private var iOSSidebarProgressSection: some View {
        Section("Progress") {
            iOSSidebarButton(.planningProgression, title: "Progression", systemImage: SFSymbol.Chart.chartLine, hint: "View student progression through curriculum")
            iOSSidebarButton(.progressDashboard, title: "Progress Dashboard", systemImage: "person.text.rectangle", hint: "View per-student progress across all subjects")
            iOSSidebarButton(.lessonFrequency, title: "Lesson Frequency", systemImage: SFSymbol.Chart.chartBar, hint: "View weekly lesson frequency per student")
            iOSSidebarButton(.curriculumBalance, title: "Curriculum Balance", systemImage: SFSymbol.Chart.chartPie, hint: "Analyze subject distribution and curriculum gaps")
            iOSSidebarButton(.greatLessonsTimeline, title: "Great Lessons", systemImage: "sparkles", hint: "View lesson progress mapped to the Five Great Lessons")
            iOSSidebarButton(.threeYearCycle, title: "Three-Year Cycle", systemImage: "chart.bar.doc.horizontal", hint: "View student progress across the three-year Montessori cycle")
            iOSSidebarButton(.transitionPlanner, title: "Transitions", systemImage: "arrow.right.arrow.left", hint: "Plan and track student transitions between levels")
        }
    }

    private var iOSSidebarResourcesSection: some View {
        Section("Resources") {
            iOSSidebarButton(.resourceLibrary, title: "Resources", systemImage: "tray.2", hint: "Browse and organize classroom resource documents")
            iOSSidebarButton(.supplies, title: "Supplies", systemImage: "shippingbox", hint: "Track classroom supplies and inventory")
            iOSSidebarButton(.procedures, title: "Procedures", systemImage: SFSymbol.CDDocument.docText, hint: "View classroom procedures and routines")
            iOSSidebarButton(.schedules, title: "Schedules", systemImage: "clock.badge.checkmark", hint: "View recurring schedules")
            iOSSidebarButton(.perpetualCalendar, title: "Calendar", systemImage: "calendar.day.timeline.leading", hint: "View perpetual year-at-a-glance calendar")
            iOSSidebarButton(.issues, title: "Issues", systemImage: "exclamationmark.triangle", hint: "Track and resolve classroom issues")
        }
    }

    private var iOSSidebarToolsSection: some View {
        Section("Tools") {
            iOSSidebarButton(.askAI, title: "Ask AI", systemImage: "bubble.left.and.text.bubble.right", hint: "Ask questions about your classroom data")
        }
    }

    private var iOSSidebarSystemSection: some View {
        Section("System") {
            iOSSidebarButton(.logs, title: "Logs", systemImage: SFSymbol.List.list, hint: "View activity and observation logs")
            iOSSidebarButton(.settings, title: "Settings", systemImage: SFSymbol.Settings.gear, hint: "Configure app preferences and sync options")
        }
    }
}
