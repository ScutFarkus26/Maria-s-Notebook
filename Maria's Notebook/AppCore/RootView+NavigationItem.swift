// RootView+NavigationItem.swift
// Navigation item enum and legacy tab enum extracted from RootView for clarity.

import SwiftUI

extension RootView {

    // MARK: - Navigation Items

    enum NavigationItem: String, Hashable, Identifiable {
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
        case planningWork
        case planningProjects
        case planningCalendar
        case progressDashboard
        case lessonRecall
        case goingOut
        case needsLesson
        case smallSequencePlanner

        case perpetualCalendar

        case community
        case schedules
        case resourceLibrary
        case askAI
        case logs
        case settings

        case thisWeeksParsha
        case parshaCalendar

        var id: Self { self }

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
            case .planningWork:        return ("Lessons & Work", "tray.full")
            case .planningProjects:    return ("Projects", "folder")
            case .planningCalendar:    return ("Calendar", "calendar.day.timeline.leading")
            case .progressDashboard:   return ("Progress Dashboard", "person.text.rectangle")
            case .lessonRecall:        return ("Lesson Recall", "arrow.clockwise.circle")
            case .goingOut:            return ("Going Out", "figure.walk")
            case .needsLesson:         return ("Needs Lesson", "clock.badge.exclamationmark")
            case .smallSequencePlanner:   return ("Group Planner", "person.3.sequence")
            case .perpetualCalendar:   return ("Calendar", "calendar.day.timeline.leading")
            case .community:           return ("Community", "bubble.left.and.bubble.right")
            case .schedules:           return ("Schedules", "clock.badge.checkmark")
            case .resourceLibrary:     return ("Resources", "tray.2")
            case .askAI:               return ("Ask AI", "bubble.left.and.text.bubble.right")
            case .logs:                return ("Logs", "list.bullet")
            case .settings:            return ("Settings", "gear")
            case .thisWeeksParsha:     return ("This Week’s Parsha", "book.closed")
            case .parshaCalendar:      return ("Parsha Calendar", "calendar")
            }
        }

        var displayName: String { metadata.displayName }
        var icon: String { metadata.icon }

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

        var isInMoreMenu: Bool {
            switch self {
            case .lessons, .teachingAlbums, .stories, .bookClub, .supplies, .procedures, .meetings,
                 .parentReports,
                 .planningChecklist, .planningAgenda,
                 .planningProjects, .planningCalendar,
                 .progressDashboard, .lessonRecall,
                 .goingOut,
                 .needsLesson, .smallSequencePlanner,
                 .perpetualCalendar,
                 .thisWeeksParsha, .parshaCalendar,
                 .community, .schedules, .resourceLibrary, .askAI, .logs, .settings:
                return true
            case .planningWork:
                // Backward-compatible destination; the visible entry is now
                // the shared Lessons & Work workspace at .planningAgenda.
                return false
            default:
                return false
            }
        }
    }

    // MARK: - Legacy Tabs (kept for backward compatibility)

    enum Tab: String, CaseIterable, Identifiable {
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
}
