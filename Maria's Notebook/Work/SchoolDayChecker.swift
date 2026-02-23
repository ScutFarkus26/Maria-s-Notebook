import Foundation
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
    /// - Parameters:
    ///   - date: The date to check
    ///   - context: ModelContext for fetching NonSchoolDay and SchoolDayOverride records
    /// - Returns: `true` if the date is a non-school day, `false` if it's a school day
    nonisolated static func isNonSchoolDay(_ date: Date, using context: ModelContext) -> Bool {
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
    nonisolated static func isSchoolDay(_ date: Date, using context: ModelContext) -> Bool {
        !isNonSchoolDay(date, using: context)
    }

    /// Counts the number of school days between two dates (exclusive of end date).
    /// - Parameters:
    ///   - start: Start date
    ///   - end: End date
    ///   - context: ModelContext for school day lookups
    /// - Returns: Number of school days between start and end
    nonisolated static func schoolDaysBetween(
        start: Date,
        end: Date,
        using context: ModelContext
    ) -> Int {
        let startDay = AppCalendar.startOfDay(start)
        let endDay = AppCalendar.startOfDay(end)

        guard startDay < endDay else { return 0 }

        var count = 0
        var cursor = startDay

        // Safety limit to prevent infinite loops
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
    /// - Parameters:
    ///   - startDate: The date to start from
    ///   - count: Number of school days to collect
    ///   - context: ModelContext for school day lookups
    /// - Returns: Array of school day dates
    nonisolated static func nextSchoolDays(
        from startDate: Date,
        count: Int,
        using context: ModelContext
    ) -> [Date] {
        var result: [Date] = []
        var cursor = AppCalendar.startOfDay(startDate)

        // Safety limit
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

    // MARK: - Private Helpers

    private nonisolated static func hasNonSchoolDayRecord(for day: Date, using context: ModelContext) -> Bool {
        do {
            var descriptor = FetchDescriptor<NonSchoolDay>(
                predicate: #Predicate { $0.date == day }
            )
            descriptor.fetchLimit = 1
            let records: [NonSchoolDay] = try context.fetch(descriptor)
            return !records.isEmpty
        } catch {
            // On fetch error, assume it's not a non-school day
            return false
        }
    }

    private nonisolated static func hasSchoolDayOverride(for day: Date, using context: ModelContext) -> Bool {
        do {
            var descriptor = FetchDescriptor<SchoolDayOverride>(
                predicate: #Predicate { $0.date == day }
            )
            descriptor.fetchLimit = 1
            let overrides: [SchoolDayOverride] = try context.fetch(descriptor)
            return !overrides.isEmpty
        } catch {
            // On fetch error, assume no override exists
            return false
        }
    }
}
