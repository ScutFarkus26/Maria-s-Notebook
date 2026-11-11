// LessonTimeText.swift
// A lesson's set start time as words: short on a chip ("10:00"), whole when
// spoken ("10:00 AM"), and the lesson sheet's status line ("Planned for
// Wednesday morning at 10:00"). Every form follows the 12- or 24-hour setting
// through the locale.
//
// Built from an hour and a minute on a fixed calendar in GMT, so neither the
// day nor a daylight-saving change can shift the clock time shown.

import Foundation

nonisolated enum LessonTimeText {

    /// The time on a card's chip: "10:00", or "13:15" where the clock is 24-hour.
    /// No AM or PM: the card already sits in its Morning or Afternoon half.
    static func chip(_ time: LessonClockTime, locale: Locale = .autoupdatingCurrent) -> String {
        clockDate(time).formatted(style(locale).hour(.defaultDigits(amPM: .omitted)).minute())
    }

    /// The time as VoiceOver says it, and wherever it stands on its own:
    /// "10:00 AM", or "10:00" where the clock is 24-hour.
    static func spoken(_ time: LessonClockTime, locale: Locale = .autoupdatingCurrent) -> String {
        clockDate(time).formatted(style(locale).hour(.defaultDigits(amPM: .abbreviated)).minute())
    }

    /// The card's spoken label gains this: "at 10:00 AM".
    static func spokenPhrase(_ time: LessonClockTime, locale: Locale = .autoupdatingCurrent) -> String {
        "at " + spoken(time, locale: locale)
    }

    /// "morning" or "afternoon", from the time itself (before noon is the morning).
    static func halfWord(_ time: LessonClockTime) -> String {
        switch time.half {
        case .morning: "morning"
        case .afternoon: "afternoon"
        }
    }

    /// The lesson sheet's status line for a scheduled lesson with a set time:
    /// "Planned for this morning at 10:00", "Planned for tomorrow afternoon at 1:30",
    /// or "Planned for Wednesday morning, Nov 12, at 10:00".
    /// `day` is any moment on the planned day, read in `calendar`; only its date is used.
    static func statusLine(
        plannedOn day: Date,
        at time: LessonClockTime,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        "Planned for " + dayPhrase(day, half: halfWord(time), now: now, calendar: calendar, locale: locale)
            + " at " + chip(time, locale: locale)
    }

    /// "this morning", "tomorrow afternoon", or "Wednesday morning, Nov 12,".
    private static func dayPhrase(
        _ day: Date, half: String, now: Date, calendar: Calendar, locale: Locale
    ) -> String {
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: day)
        let offset = calendar.dateComponents([.day], from: today, to: target).day
        switch offset {
        case 0: return "this \(half)"
        case 1: return "tomorrow \(half)"
        default:
            var weekdayStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            weekdayStyle = weekdayStyle.weekday(.wide)
            var dateStyle = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
            dateStyle = dateStyle.month(.abbreviated).day()
            return day.formatted(weekdayStyle) + " \(half), " + day.formatted(dateStyle) + ","
        }
    }

    // MARK: - Clock

    private static let gmt = TimeZone(secondsFromGMT: 0) ?? .gmt

    private static let clockCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = gmt
        return calendar
    }()

    /// The time on 2001-01-01 in GMT: a day with no daylight-saving change.
    private static func clockDate(_ time: LessonClockTime) -> Date {
        let components = DateComponents(year: 2001, month: 1, day: 1, hour: time.hour, minute: time.minute)
        return clockCalendar.date(from: components)
            ?? Date(timeIntervalSinceReferenceDate: TimeInterval(time.minutesAfterMidnight * 60))
    }

    private static func style(_ locale: Locale) -> Date.FormatStyle {
        var calendar = clockCalendar
        calendar.locale = locale
        return Date.FormatStyle(locale: locale, calendar: calendar, timeZone: gmt)
    }

    // MARK: - Picker plumbing

    /// The time as a `Date` the picker's "Another time" field can edit. Read
    /// back only with `clockTime(from:)`; never saved.
    static func fieldDate(_ time: LessonClockTime) -> Date { clockDate(time) }

    /// The hour and minute of a date made by `fieldDate(_:)`.
    static func clockTime(from fieldDate: Date) -> LessonClockTime {
        let parts = clockCalendar.dateComponents([.hour, .minute], from: fieldDate)
        return LessonClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// The time zone and calendar the "Another time" field must use so it
    /// shows `fieldDate`'s clock time unchanged.
    static var fieldTimeZone: TimeZone { gmt }
    static var fieldCalendar: Calendar { clockCalendar }
}
