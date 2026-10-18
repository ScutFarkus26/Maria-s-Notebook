// RosterBirthday.swift
// When a child's birthday next comes round, as the roster counts it.
//
// The grid card and the list row both count down to the same date and both
// worked it out for themselves; this is that one rule.
//
// A 29 February birthday counts on 28 February in a common year, the day the
// attendance tile shows the cake (`AttendanceBirthday.anniversary`). It used
// to count to 1 March, a day after the cake (bug hunt 2026-10-17, #7).

import Foundation

enum RosterBirthday {
    /// The next occurrence of `birthday`'s month and day, on or after today.
    /// A child with no birthday on file counts from today.
    static func nextOccurrence(of birthday: Date?, using calendar: Calendar, today: Date = Date()) -> Date {
        let born = calendar.dateComponents([.month, .day], from: birthday ?? today)
        guard let month = born.month, let day = born.day else { return today }
        let startOfToday = calendar.startOfDay(for: today)
        let year = calendar.component(.year, from: startOfToday)
        for candidate in [year, year + 1] {
            if let date = AttendanceBirthday.anniversary(month: month, day: day, year: candidate, calendar: calendar),
               date >= startOfToday {
                return date
            }
        }
        return today
    }
}
