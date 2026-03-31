import Foundation
import CoreData
import SwiftData

/// Centralized utility for determining school days vs non-school days.
/// Consolidates logic previously duplicated in WorkAgendaCalendarPane and WorkAging.
///
/// Rules:
/// - Explicit NonSchoolDay records mark weekdays as non-school
/// - Weekends (Saturday/Sunday) are non-school by default
/// - SchoolDayOverride can make a weekend day count as a school day
enum SchoolDayChecker {

    /// Determines if a given date is a non-school day.
    nonisolated static func isNonSchoolDay(_ date: Date, using context: NSManagedObjectContext) -> Bool {
        let day = AppCalendar.startOfDay(date)
        let cal = AppCalendar.shared

        // 1) Explicit non-school day record takes precedence
        if hasNonSchoolDayRecord(for: day, using: context) {
            return true
        }

        // 2) Check if it's a weekend (Sunday=1, Saturday=7)
        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)

        // Weekdays without explicit non-school record are school days
        guard isWeekend else { return false }

        // 3) Weekend override makes it a school day
        if hasSchoolDayOverride(for: day, using: context) {
            return false
        }

        // Default: weekends are non-school days
        return true
    }

    /// Determines if a given date is a school day (inverse of isNonSchoolDay).
    nonisolated static func isSchoolDay(_ date: Date, using context: NSManagedObjectContext) -> Bool {
        !isNonSchoolDay(date, using: context)
    }

    /// Counts the number of school days between two dates (exclusive of end date).
    nonisolated static func schoolDaysBetween(
        start: Date,
        end: Date,
        using context: NSManagedObjectContext
    ) -> Int {
        let startDay = AppCalendar.startOfDay(start)
        let endDay = AppCalendar.startOfDay(end)

        guard startDay < endDay else { return 0 }

        var count = 0
        var cursor = startDay

        let maxIterations = 36500
        var iterations = 0

        while cursor < endDay && iterations < maxIterations {
            if isSchoolDay(cursor, using: context) {
                count += 1
            }
            cursor = AppCalendar.addingDays(1, to: cursor)
            iterations += 1
        }

        return count
    }

    /// Computes a list of school days starting from a given date.
    nonisolated static func nextSchoolDays(
        from startDate: Date,
        count: Int,
        using context: NSManagedObjectContext
    ) -> [Date] {
        var result: [Date] = []
        var cursor = AppCalendar.startOfDay(startDate)

        let maxIterations = 1000
        var iterations = 0

        while result.count < count && iterations < maxIterations {
            if isSchoolDay(cursor, using: context) {
                result.append(cursor)
            }
            cursor = AppCalendar.addingDays(1, to: cursor)
            iterations += 1
        }

        return result
    }

    // MARK: - Deprecated SwiftData Bridge

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    @MainActor
    static func isNonSchoolDay(_ date: Date, using modelContext: ModelContext) -> Bool {
        let cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        return isNonSchoolDay(date, using: cdContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    @MainActor
    static func isSchoolDay(_ date: Date, using modelContext: ModelContext) -> Bool {
        !isNonSchoolDay(date, using: modelContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    @MainActor
    static func nextSchoolDays(from startDate: Date, count: Int, using modelContext: ModelContext) -> [Date] {
        let cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        return nextSchoolDays(from: startDate, count: count, using: cdContext)
    }

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    @MainActor
    static func schoolDaysBetween(start: Date, end: Date, using modelContext: ModelContext) -> Int {
        let cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        return schoolDaysBetween(start: start, end: end, using: cdContext)
    }

    // MARK: - Private Helpers

    private nonisolated static func hasNonSchoolDayRecord(for day: Date, using context: NSManagedObjectContext) -> Bool {
        let request = CDFetchRequest(CDNonSchoolDay.self)
        request.predicate = NSPredicate(format: "date == %@", day as NSDate)
        request.fetchLimit = 1
        return !context.safeFetch(request).isEmpty
    }

    private nonisolated static func hasSchoolDayOverride(for day: Date, using context: NSManagedObjectContext) -> Bool {
        let request = CDFetchRequest(CDSchoolDayOverride.self)
        request.predicate = NSPredicate(format: "date == %@", day as NSDate)
        request.fetchLimit = 1
        return !context.safeFetch(request).isEmpty
    }
}
