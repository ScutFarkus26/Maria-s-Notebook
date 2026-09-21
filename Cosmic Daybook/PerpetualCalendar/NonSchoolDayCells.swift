// NonSchoolDayCells.swift
// Turns the school calendar's non-school dates into day-grid cells.

import CoreData
import Foundation

/// The one place that asks `SchoolCalendarService` which days are not school
/// days and maps the answer onto `CellID`s for a calendar grid.
///
/// Every grid that shades non-school days — the perpetual calendar, the
/// planning calendar — loads the same set the same way, so the window
/// arithmetic and the date → cell mapping live here rather than in each view.
enum NonSchoolDayCells {

    /// The non-school days in the `years` calendar years beginning at `start`.
    static func load(
        years: Int,
        from start: Date,
        context: NSManagedObjectContext
    ) async -> Set<CellID> {
        let cal = AppCalendar.shared
        guard let end = cal.date(byAdding: .year, value: years, to: start) else { return [] }

        let dates = await SchoolCalendarService.shared.nonSchoolDays(in: start..<end, using: context)
        var cells = Set<CellID>()
        for date in dates {
            cells.insert(CellID(
                year: cal.component(.year, from: date),
                month: cal.component(.month, from: date),
                day: cal.component(.day, from: date)
            ))
        }
        return cells
    }

    /// The non-school days across whole calendar years — January 1 of the
    /// range's first year up to January 1 of the year after its last.
    static func load(
        yearRange: ClosedRange<Int>,
        context: NSManagedObjectContext
    ) async -> Set<CellID> {
        var startComps = DateComponents()
        startComps.year = yearRange.lowerBound
        startComps.month = 1
        startComps.day = 1
        guard let start = AppCalendar.shared.date(from: startComps) else { return [] }

        let years = yearRange.upperBound - yearRange.lowerBound + 1
        return await load(years: years, from: start, context: context)
    }
}
