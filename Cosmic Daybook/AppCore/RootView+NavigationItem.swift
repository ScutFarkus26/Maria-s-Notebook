// RootView+NavigationItem.swift
// Navigation item enum and legacy tab enum extracted from RootView for clarity.
//
// Where each item sits in the sidebar / tab bar is decided by
// `RootView.NavigationGroup` (RootView+NavigationGroup.swift), not here.

import SwiftUI

extension RootView {

    // MARK: - Navigation Items

    /// Every destination the root can show. Raw values are persisted in
    /// `@SceneStorage` and must never change — `NavigationGroupTests` pins
    /// each literal. Cases that are no longer destinations stay so a saved
    /// selection still decodes; see `aliases`.
    nonisolated enum NavigationItem: String, Hashable, Identifiable, CaseIterable {
        case today
        case attendance
        case note
        case students
        case parentReports
        case supplies
        case procedures
        case meetings
        case lessons
        case teachingAlbums
        case stories
        case bookClub
        case more
        case todos

        // Planning Sub-items
        case planningChecklist
        case planningAgenda
        case planningProjects
        case planningCalendar
        case progressDashboard
        case curriculumMap
        case lessonRecall
        case goingOut
        case smallSequencePlanner

        case perpetualCalendar

        case community
        case schedules
        case resourceLibrary
        case askAI
        case logs
        case notes
        case settings

        case thisWeeksParsha
        case parshaCalendar

        var id: Self { self }

        /// Cases kept only so a saved raw value still decodes; each renders as
        /// its target and appears in no navigation group.
        static let aliases: [Self: Self] = [
            .perpetualCalendar: .planningCalendar,
            .note: .today,
            .more: .today
        ]

        /// The destination this item actually shows.
        var canonical: Self { Self.aliases[self] ?? self }

        // Combines displayName + icon into one exhaustive switch,
        // so adding a new case forces updates in both at compile time.
        private var metadata: (displayName: String, icon: String) {
            switch self {
            case .today:               return ("Today", "sun.max")
            case .attendance:          return ("Attendance", "checklist")
            case .note:                return ("Note", "square.and.pencil")
            case .students:            return ("Students", "person.3")
            case .parentReports:       return ("Parent Reports", "envelope.badge.person.crop")
            case .supplies:            return ("Supplies", "shippingbox")
            case .procedures:          return ("Procedures", "doc.text")
            case .meetings:            return ("Meetings", "person.2")
            case .lessons:             return ("Lessons", "book")
            case .teachingAlbums:      return ("Albums", "books.vertical.fill")
            case .stories:             return ("Stories", "books.vertical")
            case .bookClub:            return ("Book Club", "books.vertical.circle")
            case .more:                return ("More", "ellipsis.circle")
            case .todos:               return ("Todos", "checkmark.circle")
            case .planningChecklist:   return ("Checklist", "list.clipboard")
            case .planningAgenda:      return ("Lessons & Work", "tray.full")
            case .planningProjects:    return ("Projects", "folder")
            case .planningCalendar:    return ("Calendar", "calendar.day.timeline.leading")
            case .progressDashboard:   return ("Progress Dashboard", "person.text.rectangle")
            case .curriculumMap:       return ("Three-Year View", "square.grid.3x3")
            case .lessonRecall:        return ("Lesson Recall", "arrow.clockwise.circle")
            case .goingOut:            return ("Going Out", "figure.walk")
            case .smallSequencePlanner:   return ("Group Planner", "person.3.sequence")
            case .perpetualCalendar:   return ("Calendar", "calendar.day.timeline.leading")
            case .community:           return ("Community", "bubble.left.and.bubble.right")
            case .schedules:           return ("Schedules", "clock.badge.checkmark")
            case .resourceLibrary:     return ("Resources", "tray.2")
            case .askAI:               return ("Ask AI", "bubble.left.and.text.bubble.right")
            case .logs:                return ("Logs", "list.bullet")
            case .notes:               return ("Notes", "eye")
            case .settings:            return ("Settings", "gear")
            case .thisWeeksParsha:     return ("This Week’s Parsha", "book.closed")
            case .parshaCalendar:      return ("Parsha Calendar", "calendar")
            }
        }

        var displayName: String { metadata.displayName }
        var icon: String { metadata.icon }

        /// What VoiceOver reads after the row's name in the visionOS sidebar.
        var accessibilityHint: String {
            switch self {
            case .today:               return "View today's schedule, reminders, and tasks"
            case .attendance:          return "Track daily student attendance"
            case .note:                return "Write a quick observation"
            case .students:            return "Manage student profiles and records"
            case .parentReports:       return "Draft and send monthly parent reports"
            case .supplies:            return "Track classroom supplies and inventory"
            case .procedures:          return "View classroom procedures and routines"
            case .meetings:            return "Conduct weekly student meetings"
            case .lessons:             return "Browse and manage lesson plans"
            case .teachingAlbums:      return "Read and search your Montessori teaching albums"
            case .stories:             return "Browse and import story PDFs"
            case .bookClub:            return "Manage book club packets and run sessions with students"
            case .more:                return "Everything else"
            case .todos:               return "Manage your personal todos and tasks"
            case .planningChecklist:   return "View class area checklist"
            case .planningAgenda:      return "Plan lessons, follow presentations, and manage student work"
            case .planningProjects:    return "Manage student projects"
            case .planningCalendar, .perpetualCalendar:
                return "Year-at-a-glance calendar with Mac events and due todos"
            case .progressDashboard:   return "View per-student progress across all areas"
            case .curriculumMap:       return "The curriculum against the whole class, one glyph per child and lesson"
            case .lessonRecall:        return "Re-check mastered lessons after a break"
            case .goingOut:            return "Plan and track student going-out excursions"
            case .smallSequencePlanner:   return "Find ready and almost-ready students for sequence presentations"
            case .community:           return "View community meetings and topics"
            case .schedules:           return "View recurring schedules"
            case .resourceLibrary:     return "Browse and organize classroom resource documents"
            case .askAI:               return "Ask questions about your classroom data"
            case .logs:                return "View activity and observation logs"
            case .notes:               return "Browse and search your observation notes"
            case .settings:            return "Configure app preferences and sync options"
            case .thisWeeksParsha:
                return "View this week’s Torah portion, its passages, topics, and related lessons"
            case .parshaCalendar:
                return "Annual calendar of every Shabbat and its parsha for the current Hebrew year"
            }
        }

        init?(fromLegacyTab tab: Tab) {
            switch tab {
            case .today:      self = .today
            case .attendance: self = .attendance
            case .students:   self = .students
            case .albums:     self = .lessons
            case .planning:   self = .planningAgenda
            case .community:  self = .community
            case .logs:       self = .logs
            case .settings:   self = .settings
            }
        }

    }

    // MARK: - Tab (the pre-NavigationItem selection, still decoded to migrate a saved selection)

    nonisolated enum Tab: String, CaseIterable, Identifiable {
        case students  = "Students"
        case albums    = "Lessons"
        case planning  = "Planning"
        case today     = "Today"
        case logs      = "Logs"
        case attendance = "Attendance"
        case community = "Community"
        case settings  = "Settings"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .students:  return "person.3"
            case .albums:    return "book"
            case .planning:  return "calendar"
            case .today:     return "sun.max"
            case .logs:      return "list.bullet"
            case .attendance: return "checklist"
            case .community: return "bubble.left.and.bubble.right"
            case .settings:  return "gear"
            }
        }
    }

    // MARK: - Selection restore

    /// Turns whatever the scene last saved into a destination the root can
    /// show today. Pure so the migrations are testable: retired raw values,
    /// the pre-`NavigationItem` `Tab` enum, and aliased cases all land
    /// somewhere sensible instead of falling back to Today.
    /// What `NavigationSelectionRestorer.resolve` decided.
    nonisolated struct NavigationSelectionResolution: Equatable {
        let item: NavigationItem
        /// Set when the restored destination is the Lessons & Work
        /// workspace opened on a particular lens.
        let lessonsAndWorkScope: TriageBucket?

        init(item: NavigationItem, lessonsAndWorkScope: TriageBucket? = nil) {
            self.item = item
            self.lessonsAndWorkScope = lessonsAndWorkScope
        }
    }

    nonisolated enum NavigationSelectionRestorer {

        /// The raw value of a retired navigation item that pointed at the same
        /// workspace as `.planningAgenda`, opened on the children's-work lens.
        static let retiredOpenWorkNavItemRaw = "planningWork"

        /// The retired "Needs Lesson" destination. The list it showed — which
        /// children have waited longest — now lives beside the presentations
        /// in To Schedule.
        static let retiredNeedsLessonNavItemRaw = "needsLesson"

        /// - Parameters:
        ///   - navItemRaw: `@SceneStorage("RootView.selectedNavItem")`.
        ///   - legacyTabRaw: `@SceneStorage("RootView.selectedTab")`, from
        ///     builds that still used the `Tab` enum.
        ///   - planningModeRaw: the old Planning screen's mode, consulted only
        ///     when the legacy tab was Planning.
        static func resolve(
            navItemRaw: String?,
            legacyTabRaw: String?,
            planningModeRaw: String?
        ) -> NavigationSelectionResolution {
            if let raw = navItemRaw {
                if raw == retiredOpenWorkNavItemRaw {
                    return NavigationSelectionResolution(item: .planningAgenda, lessonsAndWorkScope: .attention)
                }
                if raw == retiredNeedsLessonNavItemRaw {
                    return NavigationSelectionResolution(item: .planningAgenda, lessonsAndWorkScope: .toSchedule)
                }
                if let item = NavigationItem(rawValue: raw) {
                    return NavigationSelectionResolution(item: item.canonical)
                }
            }
            if let legacyRaw = legacyTabRaw, let legacyTab = Tab(rawValue: legacyRaw) {
                return resolveLegacyTab(legacyTab, planningModeRaw: planningModeRaw)
            }
            return NavigationSelectionResolution(item: .today)
        }

        private static func resolveLegacyTab(
            _ legacyTab: Tab,
            planningModeRaw: String?
        ) -> NavigationSelectionResolution {
            guard legacyTab == .planning else {
                let item = NavigationItem(fromLegacyTab: legacyTab) ?? .today
                return NavigationSelectionResolution(item: item.canonical)
            }
            switch planningModeRaw {
            case nil:
                return NavigationSelectionResolution(item: .planningAgenda)
            case "Open Work":
                return NavigationSelectionResolution(item: .planningAgenda, lessonsAndWorkScope: .attention)
            case "Projects":
                return NavigationSelectionResolution(item: .planningProjects)
            case "Checklist":
                return NavigationSelectionResolution(item: .planningChecklist)
            default:
                return NavigationSelectionResolution(item: .planningAgenda, lessonsAndWorkScope: .toSchedule)
            }
        }
    }
}
