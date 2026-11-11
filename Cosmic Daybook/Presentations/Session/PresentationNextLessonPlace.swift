// PresentationNextLessonPlace.swift
// Where the next lesson goes when a child is marked Ready for next on the
// presentation sheet: the Inbox, or a day, with or without a start time
// (docs/Plans/Plan - Next lesson row when presenting.md).
//
// A choice held by the sheet until Done, like every other decision there, so
// it is a plain value: a day and a clock time, never a stored moment. The
// moment is made only when Done writes it, by the planner's own rules.

import Foundation

nonisolated enum PresentationNextLessonPlace: Codable, Equatable, Hashable, Sendable {
    /// Unscheduled: it waits in the Inbox until it is given a day.
    case inbox
    /// On a day. `day` is the start of that day; `minute` is the start time as
    /// minutes after midnight, or nil for no set time.
    case on(day: Date, minute: Int?)

    init(day: Date, time: LessonClockTime? = nil) {
        self = .on(day: AppCalendar.startOfDay(day), minute: time?.minutesAfterMidnight)
    }

    /// The day, at its start, or nil for the Inbox.
    var day: Date? {
        switch self {
        case .inbox: nil
        case .on(let day, _): AppCalendar.startOfDay(day)
        }
    }

    /// The start time the guide set, if any.
    var clockTime: LessonClockTime? {
        switch self {
        case .inbox: nil
        case .on(_, let minute): minute.map(LessonClockTime.init(minutesAfterMidnight:))
        }
    }

    /// The same choice on another day; a set time goes with it.
    func moved(to day: Date) -> Self {
        .on(day: AppCalendar.startOfDay(day), minute: clockTime?.minutesAfterMidnight)
    }

    /// The same day at a start time. The Inbox stays the Inbox: a time needs a
    /// day to go with.
    func settingTime(hour: Int, minute: Int) -> Self {
        guard let day else { return self }
        return .on(day: day, minute: LessonClockTime(hour: hour, minute: minute).minutesAfterMidnight)
    }

    /// The same day with no set time.
    var removingTime: Self {
        guard let day else { return self }
        return .on(day: day, minute: nil)
    }

    /// What Done stores as the plan's scheduled moment; nil for the Inbox.
    ///
    /// A set time is written the way the card's picker writes one, so 9:00 and
    /// 2:00 on the hour stick. With no time, the lesson joins the end of the
    /// morning's hand order, behind what is already planned there.
    func scheduledMoment(using calendar: Calendar = AppCalendar.shared) -> Date? {
        guard let day else { return nil }
        if let time = clockTime {
            return DayHalfPlanner.settingTime(hour: time.hour, minute: time.minute, on: day, using: calendar)
        }
        return DayHalfPlanner.slot(DayHalfPlanner.lastSlotRank, in: .morning, on: day, using: calendar)
    }

    /// "Thursday, Nov 12", or "Thursday, Nov 12 at 10:00"; nil for the Inbox.
    func dayText(locale: Locale = .autoupdatingCurrent) -> String? {
        guard let day else { return nil }
        let date = day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().locale(locale))
        guard let time = clockTime else { return date }
        return "\(date) at \(LessonTimeText.chip(time, locale: locale))"
    }

    /// What happens to the lesson, to follow its name: "goes in the Inbox" or
    /// "is scheduled for Thursday, Nov 12 at 10:00".
    func phrase(locale: Locale = .autoupdatingCurrent) -> String {
        guard let text = dayText(locale: locale) else { return "goes in the Inbox" }
        return "is scheduled for \(text)"
    }
}
