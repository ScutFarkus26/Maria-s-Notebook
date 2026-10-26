// RosterBirthday.swift
// When a child's birthday next comes round, as the roster counts it.
//
// The grid card and the list row both count down to the same date and both
// worked it out for themselves; this is that one rule.
//
// A 29 February birthday counts on 28 February in a common year, the day the
// attendance tile shows the cake (`AttendanceBirthday.anniversary`). It used
// to count to 1 March, a day after the cake (bug hunt 2026-10-17, #7).
//
// The Hebrew birthday counts here too, for Birthdays This Week
// (docs/Plans/Plan - Hebrew birthdays.md).

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

    /// The local day of the child's next Hebrew birthday, on or after today
    /// (`HebrewBirthday`); nil with no birthday on file. `calendar` is the
    /// app's Gregorian one (`AppCalendar.shared`), never the device's, which
    /// may be set to another calendar.
    static func nextHebrewOccurrence(
        of birthday: Date?, bornAfterSunset: Bool, using calendar: Calendar = AppCalendar.shared, today: Date = Date()
    ) -> Date? {
        guard let birthday,
              let hebrew = HebrewBirthday(birthday: birthday, bornAfterSunset: bornAfterSunset, calendar: calendar)
        else { return nil }
        return hebrew.nextOccurrence(onOrAfter: today, calendar: calendar)
    }
}
