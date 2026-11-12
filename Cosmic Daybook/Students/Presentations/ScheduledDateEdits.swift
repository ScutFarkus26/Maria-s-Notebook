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

    /// Who is away with a co-teacher on one day, for the sheet's lesson
    /// (docs/Plans/Plan - Co-teacher times when scheduling.md, Phase 3): what
    /// its time picker lists and marks, and the line under the Time row. The
    /// same rules and words as the Scheduled cards (`AwayOnCards`).
    struct AwayInfo: Equatable {
        let day: AwayDay
        /// The children's short names, by upper-cased ID.
        let names: [String: String]
        /// The day's other lessons' set times.
        let ownStarts: Set<Int>

        static let empty = AwayInfo(day: .empty, names: [:], ownStarts: [])

        /// The picker's away list, marks and free times; nil with nobody away.
        func picker(children: some Sequence<UUID>) -> LessonTimeAway? {
            AwayOnCards.pickerAway(
                in: day, children: AwayDay.keys(children), ownStarts: ownStarts, name: { names[$0] }
            )
        }

        /// The card's clash line for a lesson at `minute`, when that time
        /// overlaps a group for one of the children; nil otherwise.
        func clashLine(children: some Sequence<UUID>, at minute: Int?) -> String? {
            guard let minute else { return nil }
            let note = AwayOnCards.note(
                in: day, children: AwayDay.keys(children), setMinute: minute,
                half: LessonTimeChoices.half(ofMinute: minute), name: { names[$0] }
            )
            return note?.isClash == true ? note?.line : nil
        }
    }

    /// One day's away times for a lesson with `children`, read when asked
    /// (the picker opening, the day or the children changing): one timetable
    /// fetch for the day, the children's names, and the day's other set times.
    @MainActor
    static func awayInfo(
        on day: Date,
        children: Set<UUID>,
        excluding lessonID: UUID?,
        in context: NSManagedObjectContext,
        using calendar: Calendar = AppCalendar.shared
    ) -> AwayInfo {
        let start = calendar.startOfDay(for: day)
        guard !children.isEmpty,
              let awayDay = AwayTimes.days(from: start, through: start, in: context, calendar: calendar)[start],
              !awayDay.away(children: AwayDay.keys(children)).isEmpty
        else { return .empty }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", Array(children))
        return AwayInfo(
            day: awayDay,
            names: AwayOnCards.names(context.safeFetch(request)),
            ownStarts: takenMinutes(on: day, excluding: lessonID, in: context, using: calendar)
        )
    }
}
