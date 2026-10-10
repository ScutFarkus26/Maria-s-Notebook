// TodoRepeatRule.swift
// Where a repeating todo's next occurrence lands.
//
// The 2026-10-10 bug hunt found three ways the old rule went wrong: a daily
// todo done five days late came back already overdue, a todo with only a
// When date came back with a deadline counted from the day it was done, and
// a monthly todo from the 31st slid to the 28th after February and stayed
// there. A custom repeat the editor showed as "Every 7 days" had stored 0
// and never came back at all. The rule lives here, apart from Core Data, so
// it can be tested on fixed dates.

import Foundation

nonisolated struct TodoRepeatRule: Sendable, Equatable {
    var recurrence: RecurrencePattern
    /// 0 means the editor's default, 7 (see `intervalDays`).
    var customIntervalDays: Int64
    var repeatAfterCompletion: Bool
    var dueDate: Date?
    var scheduledDate: Date?
    /// The date the occurrence before this one counted from (its deadline,
    /// else its When date), when it is still in the notebook. A month that is
    /// too short moves the 31st to the 30th or the 28th; this is how the next
    /// month gets the 31st back.
    var previousAnchorDate: Date?

    /// What a custom repeat with no interval stored repeats by: the editor
    /// shows "Every 7 days" until the stepper is touched.
    static let defaultCustomIntervalDays = 7

    var intervalDays: Int {
        customIntervalDays > 0 ? Int(customIntervalDays) : Self.defaultCustomIntervalDays
    }

    /// The next occurrence's deadline and When date, or nil when the pattern
    /// has no next date.
    ///
    /// - A todo that repeats after completion counts from `today`.
    /// - Otherwise it keeps its own schedule, counted from its deadline, or
    ///   from its When date when it has no deadline, and is moved on until it
    ///   falls after `today`: done late, it comes back on its next date, not
    ///   already due.
    /// - It keeps the kind of date it had: a When-only todo gets a When date,
    ///   never a deadline; with both, the When date keeps its distance from
    ///   the deadline; with neither, it gets a deadline counted from `today`,
    ///   as it always did.
    func nextDates(today: Date, calendar: Calendar) -> (dueDate: Date?, scheduledDate: Date?)? {
        guard recurrence != .none else { return nil }
        let startOfToday = calendar.startOfDay(for: today)
        let anchor = dueDate ?? scheduledDate
        let keepsSchedule = !repeatAfterCompletion && anchor != nil
        let base = keepsSchedule ? (anchor ?? startOfToday) : startOfToday
        let dayOfMonth = keepsSchedule ? anchorDayOfMonth(base: base, calendar: calendar)
            : calendar.component(.day, from: base)

        guard var next = step(from: base, count: 1, dayOfMonth: dayOfMonth, calendar: calendar) else { return nil }
        if keepsSchedule {
            // Months and years count from the base each time, so the day of
            // the month survives a short month; the rest step on from `next`.
            let countsFromBase = recurrence == .monthly || recurrence == .yearly
            var steps = 1
            // A bound, not a limit anyone reaches: ten years of daily repeats.
            while calendar.startOfDay(for: next) <= startOfToday, steps < 3_650 {
                steps += 1
                let later = countsFromBase
                    ? step(from: base, count: steps, dayOfMonth: dayOfMonth, calendar: calendar)
                    : step(from: next, count: 1, dayOfMonth: dayOfMonth, calendar: calendar)
                guard let later else { return nil }
                next = later
            }
        }

        if let dueDate {
            guard let scheduledDate else { return (next, nil) }
            let offset = calendar.dateComponents([.day], from: dueDate, to: scheduledDate).day ?? 0
            return (next, calendar.date(byAdding: .day, value: offset, to: next))
        }
        if scheduledDate != nil {
            return (nil, next)
        }
        return (next, nil)
    }

    /// The `count`th occurrence after `base`. A month or year lands on
    /// `dayOfMonth`, or the month's last day when it is shorter.
    private func step(from base: Date, count: Int, dayOfMonth: Int, calendar: Calendar) -> Date? {
        switch recurrence {
        case .none:
            return nil
        case .daily:
            return calendar.date(byAdding: .day, value: count, to: base)
        case .weekdays:
            return Self.adding(weekdays: count, to: base, calendar: calendar)
        case .weekly:
            return calendar.date(byAdding: .weekOfYear, value: count, to: base)
        case .biweekly:
            return calendar.date(byAdding: .weekOfYear, value: 2 * count, to: base)
        case .monthly:
            return Self.adding(months: count, to: base, dayOfMonth: dayOfMonth, calendar: calendar)
        case .yearly:
            return Self.adding(months: 12 * count, to: base, dayOfMonth: dayOfMonth, calendar: calendar)
        case .custom:
            return calendar.date(byAdding: .day, value: intervalDays * count, to: base)
        }
    }

    /// The day of the month a monthly or yearly todo is meant to fall on.
    /// When `base` is the last day of a month that was too short for the
    /// occurrence before it (Feb 28 after Jan 31), that earlier day wins.
    private func anchorDayOfMonth(base: Date, calendar: Calendar) -> Int {
        let day = calendar.component(.day, from: base)
        guard let previousAnchorDate,
              let daysInMonth = calendar.range(of: .day, in: .month, for: base)?.count,
              day == daysInMonth else { return day }
        return max(day, calendar.component(.day, from: previousAnchorDate))
    }

    /// `date` moved on by `weekdays` days that aren't Saturday or Sunday.
    static func adding(weekdays: Int, to date: Date, calendar: Calendar) -> Date? {
        var day = date
        var counted = 0
        while counted < weekdays {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return nil }
            day = next
            if !calendar.isDateInWeekend(day) { counted += 1 }
        }
        return day
    }

    /// `date` moved `months` months on, on `dayOfMonth` or the month's last
    /// day when the month is shorter, at the same time of day.
    static func adding(months: Int, to date: Date, dayOfMonth: Int, calendar: Calendar) -> Date? {
        guard let shifted = calendar.date(byAdding: .month, value: months, to: date),
              let daysInMonth = calendar.range(of: .day, in: .month, for: shifted)?.count else { return nil }
        var components = calendar.dateComponents([.era, .year, .month, .hour, .minute, .second], from: shifted)
        components.day = min(dayOfMonth, daysInMonth)
        return calendar.date(from: components)
    }
}
