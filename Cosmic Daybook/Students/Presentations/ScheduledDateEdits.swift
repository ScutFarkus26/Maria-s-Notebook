// ScheduledDateEdits.swift
// The edits the lesson's sheet makes to its scheduled date (the `Date?` it
// holds until Save, `PresentationDetailActions`): a new day from the date
// picker, a start time from the time picker, and taking the time off.
//
// Every one goes through the planner's rules (`DayHalfPlanner`), so the sheet
// stores a set time exactly as the Scheduled cards and the tools do, and a
// time survives a change of day (docs/Plans/Plan - Lesson times on cards.md,
// decisions 4 and 5).

import CoreData
import Foundation

nonisolated enum ScheduledDateEdits {

    /// `current` moved to the day `picked` falls on, keeping its time of day to
    /// the second: a set time stays the same time, and an ordering slot keeps
    /// its rank. The date picker shows days only, so its own time of day is
    /// never what the guide chose. Nil (Remove from Schedule) stays nil, and a
    /// first day (nothing scheduled before) is taken as given.
    static func changingDay(
        of current: Date?,
        to picked: Date?,
        using calendar: Calendar = AppCalendar.shared
    ) -> Date? {
        guard let picked else { return nil }
        guard let current else { return picked }
        return DayHalfPlanner.rebasing(current, onto: picked, using: calendar)
    }

    /// `current`'s day at the time the guide picked. Nil while nothing is
    /// scheduled: a time needs a day to go with.
    static func settingTime(
        hour: Int,
        minute: Int,
        on current: Date?,
        using calendar: Calendar = AppCalendar.shared
    ) -> Date? {
        guard let current else { return nil }
        return DayHalfPlanner.settingTime(hour: hour, minute: minute, on: current, using: calendar)
    }

    /// `current` with its set time taken off: same day, same half, at the end
    /// of that half's hand order. A date with no set time comes back unchanged.
    static func removingTime(from current: Date?, using calendar: Calendar = AppCalendar.shared) -> Date? {
        guard let current else { return nil }
        return DayHalfPlanner.removingTime(from: current, using: calendar)
    }

    /// The set time in `current`, for the picker and the Time row; nil for an
    /// ordering slot or no schedule.
    static func clockTime(of current: Date?, using calendar: Calendar = AppCalendar.shared) -> LessonClockTime? {
        DayHalfPlanner.setMinute(of: current, using: calendar).map(LessonClockTime.init(minutesAfterMidnight:))
    }

    /// The start times other scheduled lessons already have on `day`, which
    /// the picker dims (decision 7). `excluding` is the lesson being edited.
    static func takenMinutes(
        on day: Date,
        excluding lessonID: UUID?,
        in context: NSManagedObjectContext,
        using calendar: Calendar = AppCalendar.shared
    ) -> Set<Int> {
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "scheduledFor >= %@ AND scheduledFor < %@", start as NSDate, end as NSDate
        )
        return Set(context.safeFetch(request).compactMap { assignment in
            guard assignment.id != lessonID, !assignment.isPresented else { return nil }
            return DayHalfPlanner.setMinute(of: assignment.scheduledFor, using: calendar)
        })
    }
}
