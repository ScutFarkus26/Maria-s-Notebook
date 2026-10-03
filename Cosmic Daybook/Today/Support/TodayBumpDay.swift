// TodayBumpDay.swift
// Where Today's "move" and "bump" actions land, and what their labels call it.
//
// They land on the next school day after the day Today shows (the school
// calendar's, so a Friday's move goes to Monday and a move before a holiday
// goes past it), or after today when it shows an earlier day. Until
// 2026-10-03 they counted from the clock's today: on a Sunday, Today shows
// Monday, so a bump "to tomorrow" landed on Monday, where the lesson already
// was; on a later day it moved the lesson earlier. The labels name the day
// from the clock's today: "tomorrow" when it is tomorrow, the weekday when it
// falls within the week ("Monday"), else a short date ("Mon, Oct 12").

import Foundation

enum TodayBumpDay {

    /// The day a bump counts from: the day Today shows, or today when it shows
    /// an earlier one (an overdue item bumped from a past day must not land in
    /// the past again).
    static func base(showing shownDay: Date, now: Date, calendar: Calendar) -> Date {
        max(calendar.startOfDay(for: shownDay), calendar.startOfDay(for: now))
    }

    /// The day's name for running text: "tomorrow", "Monday", "Mon, Oct 12".
    static func name(
        for target: Date,
        today: Date,
        calendar: Calendar,
        locale: Locale = .current
    ) -> String {
        let start = calendar.startOfDay(for: today)
        let end = calendar.startOfDay(for: target)
        let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch days {
        case 1:
            return "tomorrow"
        case 2...6:
            style = style.weekday(.wide)
        default:
            style = style.weekday(.abbreviated).month(.abbreviated).day()
        }
        return target.formatted(style)
    }

    /// The same name for a menu or button title: "Tomorrow", "Monday".
    static func title(
        for target: Date,
        today: Date,
        calendar: Calendar,
        locale: Locale = .current
    ) -> String {
        let name = name(for: target, today: today, calendar: calendar, locale: locale)
        return name.prefix(1).uppercased() + name.dropFirst()
    }
}
