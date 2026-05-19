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

                sidebarRow(.attendance, title: "Attendance", systemImage: "checklist")

                sidebarRow(.prepChecklist, title: "Prep Checklist", systemImage: "checklist.checked")

                sidebarRow(.workCycle, title: "Work Cycle", systemImage: "timer")
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

                sidebarRow(.issues, title: "Issues", systemImage: "exclamationmark.triangle")
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

                sidebarRow(.stories, title: "Stories", systemImage: "books.vertical")

                sidebarRow(.bookClub, title: "Book Club", systemImage: "books.vertical.circle")

                sidebarRow(.planningProjects, title: "Projects", systemImage: SFSymbol.CDDocument.folder)
            }

            Section("Parsha") {
                sidebarRow(.thisWeeksParsha, title: "This Week’s Parsha", systemImage: "book.closed")
                sidebarRow(.parshaCalendar, title: "Parsha Calendar", systemImage: "calendar")
                sidebarRow(.parshaAlbumMatches, title: "Album Matches", systemImage: "sparkles")
                sidebarRow(.parshaCoverage, title: "Coverage", systemImage: "square.grid.2x2.fill")
                sidebarRow(.parshaTopics, title: "Topics", systemImage: "tag.fill")
            }

            Section("Planning") {
                sidebarRow(.planningCalendar, title: "Calendar", systemImage: "calendar.day.timeline.leading")

                sidebarRow(.todos, title: "Todos", systemImage: SFSymbol.Action.checkmarkCircle)

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

                sidebarRow(.smallSequencePlanner, title: "Group Planner", systemImage: "person.3.sequence")

                sidebarRow(.planningChecklist, title: "Checklist", systemImage: "list.clipboard")
            }

            Section("Insights") {
                sidebarRow(.planningProgression, title: "Progression", systemImage: SFSymbol.Chart.chartLine)

                sidebarRow(.progressDashboard, title: "Progress Dashboard", systemImage: "person.text.rectangle")

                sidebarRow(.transitionPlanner, title: "Transitions", systemImage: "arrow.right.arrow.left")

                sidebarRow(.fridayReview, title: "Friday Review", systemImage: "checkmark.seal")

                sidebarRow(.lessonFrequency, title: "Lesson Frequency", systemImage: SFSymbol.Chart.chartBar)

                sidebarRow(.curriculumBalance, title: "Curriculum Balance", systemImage: SFSymbol.Chart.chartPie)

                sidebarRow(.greatLessonsTimeline, title: "Great Lessons", systemImage: "sparkles")

                sidebarRow(.threeYearCycle, title: "Three-Year Cycle", systemImage: "chart.bar.doc.horizontal")
            }

            Section("Resources") {
                sidebarRow(.resourceLibrary, title: "Resources", systemImage: "tray.2")

                sidebarRow(.supplies, title: "Supplies", systemImage: "shippingbox")

                sidebarRow(.procedures, title: "Procedures", systemImage: SFSymbol.CDDocument.docText)

                sidebarRow(.schedules, title: "Schedules", systemImage: "clock.badge.checkmark")
            }

            Section("System") {
                sidebarRow(.askAI, title: "Ask AI", systemImage: "bubble.left.and.text.bubble.right")
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
            iOSSidebarParshaSection
            iOSSidebarPlanningSection
            iOSSidebarInsightsSection
            iOSSidebarResourcesSection
            iOSSidebarSystemSection
        }
    }

    private func iOSSidebarButton(
        _ item: RootView.NavigationItem,
        title: String,
        systemImage: String,
        hint: String
    ) -> some View {
        Button { selection = item } label: {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .accessibilityHint(hint)
    }

    private var iOSSidebarTodaySection: some View {
        Section("Today") {
            iOSSidebarButton(.today,
                             title: "Today",
                             systemImage: SFSymbol.Weather.sun,
                             hint: "View today's schedule, reminders, and tasks")
            iOSSidebarButton(.attendance,
                             title: "Attendance",
                             systemImage: "checklist",
                             hint: "Track daily student attendance")
            iOSSidebarButton(.prepChecklist,
                             title: "Prep Checklist",
                             systemImage: "checklist.checked",
                             hint: "Daily classroom environment preparation checklist")
            iOSSidebarButton(.workCycle,
                             title: "Work Cycle",
                             systemImage: "timer",
                             hint: "Track student activity during the work cycle")
        }
    }

    private var iOSSidebarStudentsSection: some View {
        Section("Students") {
            iOSSidebarButton(.students,
                             title: "Students",
                             systemImage: SFSymbol.People.person3,
                             hint: "Manage student profiles and records")
            iOSSidebarButton(.meetings,
                             title: "Meetings",
                             systemImage: SFSymbol.People.person2,
                             hint: "Conduct weekly student meetings")
            iOSSidebarButton(.goingOut,
                             title: "Going Out",
                             systemImage: "figure.walk",
                             hint: "Plan and track student going-out excursions")
            iOSSidebarButton(.parentCommunication,
                             title: "Parent Comms",
                             systemImage: "envelope",
                             hint: "Draft and track parent communications")
        }
    }

    private var iOSSidebarClassroomSection: some View {
        Section("Classroom") {
            iOSSidebarButton(.community,
                             title: "Community",
                             systemImage: "bubble.left.and.bubble.right",
                             hint: "View community meetings and topics")
            iOSSidebarButton(.classroomJobs,
                             title: "Jobs",
                             systemImage: "person.2.badge.gearshape",
                             hint: "Manage classroom job rotation board")
            iOSSidebarButton(.issues,
                             title: "Issues",
                             systemImage: "exclamationmark.triangle",
                             hint: "Track and resolve classroom issues")
        }
    }

    private var iOSSidebarCurriculumSection: some View {
        Section("Curriculum") {
            iOSSidebarButton(.lessons,
                             title: "Lessons",
                             systemImage: SFSymbol.Education.book,
                             hint: "Browse and manage lesson plans")
            iOSSidebarButton(.stories,
                             title: "Stories",
                             systemImage: "books.vertical",
                             hint: "Browse and import story PDFs")
            iOSSidebarButton(.bookClub,
                             title: "Book Club",
                             systemImage: "books.vertical.circle",
                             hint: "Manage book club packets and run sessions with students")
            iOSSidebarButton(.planningProjects,
                             title: "Projects",
                             systemImage: SFSymbol.CDDocument.folder,
                             hint: "Manage student projects")
        }
    }

    private var iOSSidebarParshaSection: some View {
        Section("Parsha") {
            iOSSidebarButton(.thisWeeksParsha,
                             title: "This Week’s Parsha",
                             systemImage: "book.closed",
                             hint: "View this week’s Torah portion, its passages, topics, and related lessons")
            iOSSidebarButton(.parshaCalendar,
                             title: "Parsha Calendar",
                             systemImage: "calendar",
                             hint: "Annual calendar of every Shabbat and its parsha for the current Hebrew year")
            iOSSidebarButton(.parshaAlbumMatches,
                             title: "Album Matches",
                             systemImage: "sparkles",
                             hint: "AI-suggested album lessons whose themes connect to each parsha")
            iOSSidebarButton(.parshaCoverage,
                             title: "Coverage",
                             systemImage: "square.grid.2x2.fill",
                             hint: "See which parshas have lessons and which still need them")
            iOSSidebarButton(.parshaTopics,
                             title: "Topics",
                             systemImage: "tag.fill",
                             hint: "Browse parshas by topic — pick a theme to see which parshas mention it")
        }
    }

    private var iOSSidebarPlanningSection: some View {
        Section("Planning") {
            iOSSidebarButton(.planningCalendar,
                             title: "Calendar",
                             systemImage: "calendar.day.timeline.leading",
                             hint: "Year-at-a-glance calendar with Mac events and due todos")
            iOSSidebarButton(.todos,
                             title: "Todos",
                             systemImage: SFSymbol.Action.checkmarkCircle,
                             hint: "Manage your personal todos and tasks")
            iOSSidebarButton(.planningAgenda,
                             title: "Presentations",
                             systemImage: SFSymbol.Time.calendar,
                             hint: "Manage lesson presentations agenda")
            iOSSidebarButton(.planningWork,
                             title: "Open Work",
                             systemImage: "tray.full",
                             hint: "View and manage student work")
            iOSSidebarButton(.needsLesson,
                             title: "Needs Lesson",
                             systemImage: "clock.badge.exclamationmark",
                             hint: "See which students need a lesson based on days since last presentation")
            iOSSidebarButton(.smallSequencePlanner,
                             title: "Group Planner",
                             systemImage: "person.3.sequence",
                             hint: "Find ready and almost-ready students for sequence presentations")
            iOSSidebarButton(.planningChecklist,
                             title: "Checklist",
                             systemImage: "list.clipboard",
                             hint: "View class area checklist")
        }
    }

    private var iOSSidebarInsightsSection: some View {
        Section("Insights") {
            iOSSidebarButton(.planningProgression,
                             title: "Progression",
                             systemImage: SFSymbol.Chart.chartLine,
                             hint: "View student progression through curriculum")
            iOSSidebarButton(.progressDashboard,
                             title: "Progress Dashboard",
                             systemImage: "person.text.rectangle",
                             hint: "View per-student progress across all areas")
            iOSSidebarButton(.transitionPlanner,
                             title: "Transitions",
                             systemImage: "arrow.right.arrow.left",
                             hint: "Plan and track student transitions between levels")
            iOSSidebarButton(.fridayReview,
                             title: "Friday Review",
                             systemImage: "checkmark.seal",
                             hint: "Review the week and prepare Monday priorities")
            iOSSidebarButton(.lessonFrequency,
                             title: "Lesson Frequency",
                             systemImage: SFSymbol.Chart.chartBar,
                             hint: "View weekly lesson frequency per student")
            iOSSidebarButton(.curriculumBalance,
                             title: "Curriculum Balance",
                             systemImage: SFSymbol.Chart.chartPie,
                             hint: "Analyze area distribution and curriculum gaps")
            iOSSidebarButton(.greatLessonsTimeline,
                             title: "Great Lessons",
                             systemImage: "sparkles",
                             hint: "View lesson progress mapped to the Five Great Lessons")
            iOSSidebarButton(.threeYearCycle,
                             title: "Three-Year Cycle",
                             systemImage: "chart.bar.doc.horizontal",
                             hint: "View student progress across the three-year Montessori cycle")
        }
    }

    private var iOSSidebarResourcesSection: some View {
        Section("Resources") {
            iOSSidebarButton(.resourceLibrary,
                             title: "Resources",
                             systemImage: "tray.2",
                             hint: "Browse and organize classroom resource documents")
            iOSSidebarButton(.supplies,
                             title: "Supplies",
                             systemImage: "shippingbox",
                             hint: "Track classroom supplies and inventory")
            iOSSidebarButton(.procedures,
                             title: "Procedures",
                             systemImage: SFSymbol.CDDocument.docText,
                             hint: "View classroom procedures and routines")
            iOSSidebarButton(.schedules,
                             title: "Schedules",
                             systemImage: "clock.badge.checkmark",
                             hint: "View recurring schedules")
        }
    }

    private var iOSSidebarSystemSection: some View {
        Section("System") {
            iOSSidebarButton(.askAI,
                             title: "Ask AI",
                             systemImage: "bubble.left.and.text.bubble.right",
                             hint: "Ask questions about your classroom data")
            iOSSidebarButton(.logs,
                             title: "Logs",
                             systemImage: SFSymbol.List.list,
                             hint: "View activity and observation logs")
            iOSSidebarButton(.settings,
                             title: "Settings",
                             systemImage: SFSymbol.Settings.gear,
                             hint: "Configure app preferences and sync options")
        }
    }
}
