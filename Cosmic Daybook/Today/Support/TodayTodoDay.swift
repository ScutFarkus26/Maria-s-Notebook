// TodayTodoDay.swift
// The days Today's to-do section reads, which on a weekend or a day off are
// not just the school day the screen shows.

import Foundation

/// Today shows the nearest school day: on a Saturday it shows Friday, on a
/// Sunday Monday. Its to-dos followed that day, so on Saturday a to-do
/// planned or due Saturday (the When popover's "Today") was hidden, and on
/// Sunday Sunday's showed as overdue; the Todos screen, which reads the real
/// day, disagreed (bug hunt 2026-11-03 #53). When the shown day is the one
/// Today moved the real day to, the to-dos read the real day as today and
/// include everything dated up to the shown day as well.
struct TodayTodoDay: Equatable {
    /// A to-do due before this day is overdue.
    let overdueBefore: Date
    /// The last day whose planned and due to-dos are listed.
    let lastDay: Date

    /// - Parameters:
    ///   - shownDay: the day Today shows.
    ///   - realDay: the calendar day it is.
    ///   - schoolDayForRealDay: the school day Today moves `realDay` to
    ///     (the same day on a school day).
    init(shownDay: Date, realDay: Date, schoolDayForRealDay: Date) {
        let shown = AppCalendar.startOfDay(shownDay)
        let real = AppCalendar.startOfDay(realDay)
        if shown == AppCalendar.startOfDay(schoolDayForRealDay) && shown != real {
            overdueBefore = real
            lastDay = max(real, shown)
        } else {
            overdueBefore = shown
            lastDay = shown
        }
    }

    /// The When date the + button's new to-do starts with, so it shows on
    /// the screen it was added on (bug hunt 2026-11-03 #54): the shown day,
    /// or the real day when that is later (a Saturday showing Friday).
    var newTodoDate: Date { lastDay }
}
