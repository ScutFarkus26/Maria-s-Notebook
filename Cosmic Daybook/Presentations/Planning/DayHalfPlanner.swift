// DayHalfPlanner.swift
// Which half of the day a scheduled presentation sits in, and how a stored
// moment is read back as a half or a time.
//
// A scheduled presentation has no time — the guide plans an order, not a
// timetable — so `scheduledFor` carries that order as second-spaced offsets
// from a base hour. That leaves exactly one thing still worth saying about
// *when*: morning or afternoon. The base hour now says it. Morning items count
// up from 9, afternoon items from 2, and nothing new is stored: the halves are
// read back out of the hour. Nothing is added to the Core Data model either,
// which matters here — the model is CloudKit-mirrored and edited in place.
//
// Numbering per half rather than across the whole day is what keeps the two
// apart. Six morning lessons and one afternoon lesson are 9:00:00–9:00:05 and
// 14:00:00, so no amount of reordering can walk the morning run into the
// afternoon, and the day still sorts top to bottom in the order it will be
// taught — every morning offset is before noon and every afternoon one after.

import Foundation

// `DayPeriod` itself is declared in Planning/PlanningModels.swift, with the
// label, colour and base hour the planning screens already used.
extension DayPeriod {
    /// What a card shows: two characters, which is all a pill has room for
    /// beside a lesson title and a row of student chips. `label` is the spoken
    /// form, and what the menu offers.
    var abbreviation: String {
        switch self {
        case .morning: return "AM"
        case .afternoon: return "PM"
        }
    }

    /// The half an already-scheduled moment falls in.
    ///
    /// Noon is the only boundary that matters here, not the base hours: a
    /// deliberate 10:30 is still a morning, and the rows written before the
    /// halves existed sit at midnight, which reads as morning too — the same
    /// half the ordering base has always used.
    init(scheduledFor date: Date, using calendar: Calendar = AppCalendar.shared) {
        self = calendar.component(.hour, from: date) < 12 ? .morning : .afternoon
    }

    /// `date` moved into this half, at this half's base hour.
    ///
    /// The minute and second come along because that is where a presentation's
    /// position within its day is kept — 9:00:05 is the sixth lesson of the
    /// morning, and flipping it to the afternoon should make it the sixth
    /// there, not flatten it onto whatever is already at 2:00 sharp. The hour
    /// is not kept: there is no time here to preserve, and carrying a 10 across
    /// would turn a morning lesson into a 10pm one.
    func applied(to date: Date, using calendar: Calendar = AppCalendar.shared) -> Date {
        let parts = calendar.dateComponents([.minute, .second], from: date)
        return calendar.date(
            bySettingHour: baseHour,
            minute: parts.minute ?? 0,
            second: parts.second ?? 0,
            of: date
        ) ?? date
    }
}

/// What a stored `scheduledFor` actually says about *when*.
///
/// The encoding above means a scheduled moment is one of two quite different
/// things, and a reader that prints it as a wall clock reports the wrong one:
/// every ordering slot comes back "09:00" or "14:00", which is a time nobody
/// set and which hides the real distinction — morning versus afternoon.
enum ScheduledMoment: Equatable, Sendable {
    /// An ordering slot: the guide chose a half of the day, not a time.
    case half(DayPeriod)
    /// A time the guide actually set, from the time picker or a tool's `time:`.
    case time(Date)
}

/// Reads a stored `scheduledFor` back as a half or a time. No Core Data, so
/// it is testable without a store.
enum DayHalfPlanner {
    /// Reads a stored moment back as the thing it was written to mean.
    ///
    /// An ordering slot is a base hour on the minute — the rank lives in the
    /// seconds, so `9:00:07` is the eighth lesson of the morning and not seven
    /// past nine. Midnight is the same answer for rows written before the halves
    /// existed, matching `DayPeriod(scheduledFor:)`, which has always read them
    /// as mornings. Everything else is a deliberate time.
    ///
    /// The accepted limit: an explicit 09:00 or 14:00 reads back as a half.
    /// "In the morning" is still true of a nine o'clock lesson, which is why
    /// this is the safe direction to be wrong in.
    static func moment(
        of date: Date,
        using calendar: Calendar = AppCalendar.shared
    ) -> ScheduledMoment {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        let minute = parts.minute ?? 0
        if minute == 0 {
            if hour == 0 { return .half(.morning) }
            for period in DayPeriod.allCases where period.baseHour == hour {
                return .half(period)
            }
        }
        return .time(date)
    }
}
