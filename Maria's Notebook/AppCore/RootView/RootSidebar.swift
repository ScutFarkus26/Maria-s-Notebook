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

                sidebarRow(.parentReports, title: "Parent Reports", systemImage: "envelope.badge.person.crop")

                sidebarRow(.goingOut, title: "Going Out", systemImage: "figure.walk")

                sidebarRow(.progressDashboard, title: "Progress Dashboard", systemImage: "person.text.rectangle")

                sidebarRow(.lessonRecall, title: "Lesson Recall", systemImage: "arrow.clockwise.circle")
            }

            Section("Planning") {
                sidebarRow(.planningCalendar, title: "Calendar", systemImage: "calendar.day.timeline.leading")

                sidebarRow(.todos, title: "Todos", systemImage: SFSymbol.Action.checkmarkCircle)

                sidebarRow(.planningAgenda, title: "Lessons & Work", systemImage: "tray.full")
                .contextMenu {
                    Button {
                        appRouter.triggerNewPresentation = true
                    } label: {
                        Label("New Presentation…", systemImage: "calendar.badge.plus")
                    }

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

            Section("Classroom") {
                sidebarRow(.community, title: "Community", systemImage: "bubble.left.and.bubble.right")
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

                sidebarRow(.teachingAlbums, title: "Albums", systemImage: "books.vertical.fill")

                sidebarRow(.stories, title: "Stories", systemImage: "books.vertical")

                sidebarRow(.bookClub, title: "Book Club", systemImage: "books.vertical.circle")

                sidebarRow(.planningProjects, title: "Projects", systemImage: SFSymbol.CDDocument.folder)
            }

            Section("Parsha") {
                sidebarRow(.thisWeeksParsha, title: "This Week’s Parsha", systemImage: "book.closed")
                sidebarRow(.parshaCalendar, title: "Parsha Calendar", systemImage: "calendar")
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
            iOSSidebarPlanningSection
            iOSSidebarClassroomSection
            iOSSidebarCurriculumSection
            iOSSidebarParshaSection
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
            iOSSidebarButton(.progressDashboard,
                             title: "Progress Dashboard",
                             systemImage: "person.text.rectangle",
                             hint: "View per-student progress across all areas")
            iOSSidebarButton(.lessonRecall,
                             title: "Lesson Recall",
                             systemImage: "arrow.clockwise.circle",
                             hint: "Re-check mastered lessons after a break")
        }
    }

    private var iOSSidebarClassroomSection: some View {
        Section("Classroom") {
            iOSSidebarButton(.community,
                             title: "Community",
                             systemImage: "bubble.left.and.bubble.right",
                             hint: "View community meetings and topics")
        }
    }

    private var iOSSidebarCurriculumSection: some View {
        Section("Curriculum") {
            iOSSidebarButton(.lessons,
                             title: "Lessons",
                             systemImage: SFSymbol.Education.book,
                             hint: "Browse and manage lesson plans")
            iOSSidebarButton(.teachingAlbums,
                             title: "Albums",
                             systemImage: "books.vertical.fill",
                             hint: "Read and search your Montessori teaching albums")
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
                             title: "Lessons & Work",
                             systemImage: "tray.full",
                             hint: "Plan lessons, follow presentations, and manage student work")
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
