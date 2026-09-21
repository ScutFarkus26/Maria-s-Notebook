// RosterBirthday.swift
// When a child's birthday next comes round, as the roster counts it.
//
// The grid card and the list row both count down to the same date and both
// worked it out for themselves; this is that one rule.
//
// Note it is not `AgeUtils.nextBirthday`, which resolves a 29 February
// birthday to 28 February in a common year where this one lets the calendar
// roll it to 1 March. The two were already different, and making them agree is
// a behaviour change, not a cleanup.

import Foundation

enum RosterBirthday {
    /// The next occurrence of `birthday`'s month and day, on or after today.
    /// A child with no birthday on file counts from today.
    static func nextOccurrence(of birthday: Date?, using calendar: Calendar) -> Date {
        let today = Date()
        let comps = calendar.dateComponents([.month, .day], from: birthday ?? today)
        let currentYear = calendar.component(.year, from: today)
        var thisYear = calendar.date(from: DateComponents(year: currentYear, month: comps.month, day: comps.day))
        // Handle Feb 29 on non-leap years by using Feb 28
        if thisYear == nil, comps.month == 2, comps.day == 29 {
            thisYear = calendar.date(from: DateComponents(year: currentYear, month: 2, day: 28))
        }
        guard let this = thisYear else { return today }
        let startOfToday = calendar.startOfDay(for: today)
        if this >= startOfToday { return this }
        let nextYear = currentYear + 1
        var next = calendar.date(from: DateComponents(year: nextYear, month: comps.month, day: comps.day))
        if next == nil, comps.month == 2, comps.day == 29 {
            next = calendar.date(from: DateComponents(year: nextYear, month: 2, day: 28))
        }
        return next ?? this
    }
}
