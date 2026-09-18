//
//  YearPlanPacing.swift
//  Cosmic Daybook
//
//  Where a target date is allowed to land.
//
//  A year-plan target is a day the guide intends to give a lesson, so it can
//  only be a day the school is open. The app has always known which days those
//  are — `SchoolCalendarService` reads the explicit non-school days and the
//  weekend rules, and every screen that asks "is school in session?" goes
//  through it — but only some of the paths that write a target date asked.
//  Fanning a sequence out spaced its entries by *school* days and got this
//  right; the first entry of that fan-out, a drag onto a calendar cell, and
//  `update_year_plan_entry` all wrote whatever day they were handed. That is
//  how thirteen children ended up with a lesson targeted at Rosh Hashana.
//
//  Two rules, and both are here so they cannot drift:
//
//  - A target only ever moves **forward** to an open day. Moving it back would
//    make a lesson due earlier than the guide asked for, and could make it
//    behind pace the moment it was written.
//  - A run of targets swallowed by a break does not pile up on the morning
//    school reopens. The first one lands on that morning; the rest cascade
//    from it by their own `spacingSchoolDays`, so a week of Sukkos costs the
//    sequence a week, not its spacing.
//

import CoreData
import Foundation

enum YearPlanPacing {

    /// The first open day at or after `date`. An open day is returned unchanged.
    static func schoolDay(onOrAfter date: Date, in context: NSManagedObjectContext) -> Date {
        let day = AppCalendar.startOfDay(date)
        guard SchoolCalendarService.shared.isNonSchoolDaySync(day, using: context) else { return day }
        return SchoolCalendarService.shared.nextSchoolDaySync(after: day, using: context)
    }

    /// `count` school days after `date`, skipping everything the school is
    /// closed for. Always lands on an open day.
    static func advance(
        from date: Date, bySchoolDays count: Int64, in context: NSManagedObjectContext
    ) -> Date {
        var cursor = AppCalendar.startOfDay(date)
        for _ in 0..<max(1, count) {
            cursor = SchoolCalendarService.shared.nextSchoolDaySync(after: cursor, using: context)
        }
        return cursor
    }

    /// Lays a sequence's targets back onto open days, in order.
    ///
    /// Each entry keeps its own date if that date is an open day and still
    /// falls after the entry before it. Otherwise it moves: the first entry of
    /// a run inside a break goes to the morning school reopens, and each one
    /// after it cascades from the entry before by its own spacing. An entry
    /// after the break that would now be out of order is carried along, so a
    /// sequence never reads lesson five before lesson four.
    ///
    /// - Parameter entries: one sequence, in the order it is to be given.
    /// - Returns: how many targets moved.
    @discardableResult
    static func resettle(
        _ entries: [CDYearPlanEntry], in context: NSManagedObjectContext
    ) -> Int {
        var previous: Date?
        var moved = 0

        for entry in entries {
            guard let current = entry.plannedDate else { continue }
            var target = schoolDay(onOrAfter: current, in: context)
            if let previous, target <= previous {
                target = advance(from: previous, bySchoolDays: entry.spacingSchoolDays, in: context)
            }
            if target != AppCalendar.startOfDay(current) {
                entry.plannedDate = target
                entry.modifiedAt = Date()
                moved += 1
            }
            previous = target
        }
        return moved
    }

    /// The order a sequence is given in: its own numbering first, and the
    /// target date to break ties for entries that were never numbered.
    static func inSequenceOrder(_ entries: [CDYearPlanEntry]) -> [CDYearPlanEntry] {
        entries.sorted { lhs, rhs in
            if lhs.orderInSequence != rhs.orderInSequence {
                return lhs.orderInSequence < rhs.orderInSequence
            }
            return (lhs.plannedDate ?? .distantFuture) < (rhs.plannedDate ?? .distantFuture)
        }
    }

    /// Whether this target sits on a day the school is closed.
    static func fallsOnClosedDay(
        _ entry: CDYearPlanEntry, in context: NSManagedObjectContext
    ) -> Bool {
        guard let date = entry.plannedDate else { return false }
        return SchoolCalendarService.shared.isNonSchoolDaySync(date, using: context)
    }
}
