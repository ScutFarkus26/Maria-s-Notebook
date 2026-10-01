// RosterSignals.swift
// What the roster says about each child, the same on every platform and in
// every sort: presence today, school days since the last lesson, when the
// child was last observed, and the next lesson picked for them.
//
// The Mac table, the iPad cards and the iPhone rows used to show three
// different things; this is the one vocabulary they now share.

import Foundation

/// One child's roster signals, assembled from `StudentsViewModel`'s caches.
struct StudentSignals: Equatable {
    enum Presence: Equatable {
        /// No mark yet today.
        case unmarked
        /// Present or tardy: a late arrival is still here.
        case here
        case absent
        case leftEarly
    }

    var presence: Presence = .unmarked
    /// School days since the last presented lesson; nil when there is none in
    /// the last year.
    var schoolDaysSinceLesson: Int?
    var lastObserved: Date?
    var nextLessonName: String?

    /// True when the child has had no lesson in a year, or
    /// `RosterSignalRules.dueSchoolDays` or more school days have passed since
    /// the last one.
    var isDueForLesson: Bool {
        RosterSignalRules.isDue(schoolDaysSinceLesson: schoolDaysSinceLesson)
    }

    func isObservationStale(now: Date = Date(), calendar: Calendar = AppCalendar.shared) -> Bool {
        RosterSignalRules.isObservationStale(lastObserved, now: now, calendar: calendar)
    }
}

/// The thresholds behind the roster's orange text and the Due scope.
enum RosterSignalRules {
    /// Matches Today's "need a lesson" count, so the two screens agree.
    static let dueSchoolDays = 7
    /// Calendar days without an observation before the roster flags it.
    static let observationStaleDays = 14
    /// How far ahead a birthday shows on a child's name: the coming six days,
    /// so a weekday name ("Birthday Tue") never means a week from today.
    static let birthdaySoonDays = 6

    static func isDue(schoolDaysSinceLesson days: Int?) -> Bool {
        guard let days else { return true }
        return days >= dueSchoolDays
    }

    static func isObservationStale(_ date: Date?, now: Date, calendar: Calendar) -> Bool {
        guard let date else { return true }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0
        return days >= observationStaleDays
    }

    /// Days until the child's next birthday, when it falls within
    /// `birthdaySoonDays` (0 = today); nil otherwise or with no birthday on file.
    static func daysUntilSoonBirthday(_ birthday: Date?, calendar: Calendar, today: Date = Date()) -> Int? {
        guard let birthday else { return nil }
        let next = RosterBirthday.nextOccurrence(of: birthday, using: calendar, today: today)
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: today), to: calendar.startOfDay(for: next)
        ).day ?? .max
        return days <= birthdaySoonDays ? days : nil
    }
}

/// The roster's wording for each signal, shared by rows, the table and the
/// class-at-a-glance page.
enum RosterSignalText {
    /// "Lesson today", "Lesson 11 days ago", "No lessons this year".
    static func lesson(_ schoolDays: Int?) -> String {
        switch schoolDays {
        case nil: return "No lessons this year"
        case 0: return "Lesson today"
        case 1: return "Lesson 1 day ago"
        case let days?: return "Lesson \(days) days ago"
        }
    }

    /// Just the count, for a table column: "Today", "11 days", "No lessons".
    static func lessonShort(_ schoolDays: Int?) -> String {
        switch schoolDays {
        case nil: return "No lessons"
        case 0: return "Today"
        case 1: return "1 day"
        case let days?: return "\(days) days"
        }
    }

    /// "Observed today", "Observed 3 days ago", "Observed 3 wks ago", "Never observed".
    static func observed(_ date: Date?, calendar: Calendar, now: Date = Date()) -> String {
        guard date != nil else { return "Never observed" }
        return "Observed \(observedShort(date, calendar: calendar, now: now).lowercased())"
    }

    /// "Today", "Yesterday", "3 days ago", "3 wks ago", "Never".
    static func observedShort(_ date: Date?, calendar: Calendar, now: Date = Date()) -> String {
        guard let date else { return "Never" }
        let days = calendar.dateComponents(
            [.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)
        ).day ?? 0
        switch days {
        case ..<1: return "Today"
        case 1: return "Yesterday"
        case 2..<14: return "\(days) days ago"
        default: return "\(days / 7) wks ago"
        }
    }

    /// "Birthday today", or "Birthday Tue" within the week.
    static func birthday(inDays days: Int, calendar: Calendar, today: Date = Date()) -> String {
        guard days > 0 else { return "Birthday today" }
        let date = calendar.date(byAdding: .day, value: days, to: today) ?? today
        return "Birthday \(date.formatted(.dateTime.weekday(.abbreviated)))"
    }
}
