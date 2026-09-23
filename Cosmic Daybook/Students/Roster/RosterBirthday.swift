// RosterBirthday.swift
// When a child's birthday next comes round, as the roster counts it.
//
// The grid card and the list row both count down to the same date and both
// worked it out for themselves; this is that one rule.
//
// A 29 February birthday counts on 28 February in a common year, the
// `AgeUtils.nextBirthday` rule.

import Foundation

enum RosterBirthday {
    /// The next occurrence of `birthday`'s month and day, on or after today.
    /// A child with no birthday on file counts from today.
    static func nextOccurrence(of birthday: Date?, using calendar: Calendar, today: Date = Date()) -> Date {
        AgeUtils.nextBirthday(for: birthday ?? today, today: today, calendar: calendar) ?? today
    }
}
