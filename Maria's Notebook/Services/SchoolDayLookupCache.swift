import Foundation
import CoreData

/// A cache for school day lookups that pre-fetches all NonSchoolDay and SchoolDayOverride
/// records to enable O(1) lookups instead of repeated database queries.
///
/// This solves the N+1 query problem when computing school days between dates.
///
/// Usage:
/// ```swift
/// let cache = SchoolDayLookupCache()
/// cache.preload(using: context)
/// let isNonSchool = cache.isNonSchoolDay(date)
/// ```
@MainActor
final class SchoolDayLookupCache {
    private var nonSchoolDays: Set<Date>?
    private var schoolDayOverrides: Set<Date>?
    private var computedDays: [Date: Bool] = [:]

    init() {}

    // MARK: - Core Data Preload

    /// Preload all school day data from the database using Core Data.
    /// Call this once before using `isNonSchoolDay` or `isSchoolDay`.
    func preload(using context: NSManagedObjectContext) {
        let nonSchoolRequest = CDFetchRequest(CDNonSchoolDay.self)
        let nonSchool = context.safeFetch(nonSchoolRequest)
        nonSchoolDays = Set(nonSchool.compactMap { $0.date.map { AppCalendar.startOfDay($0) } })

        let overrideRequest = CDFetchRequest(CDSchoolDayOverride.self)
        let overrides = context.safeFetch(overrideRequest)
        schoolDayOverrides = Set(overrides.compactMap { $0.date.map { AppCalendar.startOfDay($0) } })
    }

    // Deprecated SwiftData preload removed - no longer needed with Core Data.

    // MARK: - Lookups

    /// Check if a date is a non-school day (O(1) lookup after preload).
    /// Returns true for:
    /// - Explicit non-school days
    /// - Weekends without an override
    func isNonSchoolDay(_ date: Date) -> Bool {
        let day = AppCalendar.startOfDay(date)

        // Check memoization cache first
        if let cached = computedDays[day] {
            return cached
        }

        // Compute and cache
        let result = computeIsNonSchoolDay(day)
        computedDays[day] = result
        return result
    }

    /// Check if a date is a school day (inverse of isNonSchoolDay).
    func isSchoolDay(_ date: Date) -> Bool {
        !isNonSchoolDay(date)
    }

    /// Count school days between two dates (exclusive of end date).
    func schoolDaysBetween(start: Date, end: Date) -> Int {
        let startDay = AppCalendar.startOfDay(start)
        let endDay = AppCalendar.startOfDay(end)
        var count = 0
        var cursor = startDay

        while cursor < endDay {
            if !isNonSchoolDay(cursor) {
                count += 1
            }
            cursor = AppCalendar.addingDays(1, to: cursor)
            // Safety limit to prevent infinite loops
            assert(count < BatchingConstants.maxDaysToIterate, "Date iteration safety limit exceeded")
            if count > BatchingConstants.maxDaysToIterate { break }
        }

        return max(0, count)
    }

    /// Invalidate all cached data. Call this when school day data changes.
    func invalidate() {
        nonSchoolDays = nil
        schoolDayOverrides = nil
        computedDays.removeAll()
    }

    /// Check if the cache has been preloaded.
    var isPreloaded: Bool {
        nonSchoolDays != nil && schoolDayOverrides != nil
    }

    // MARK: - Private

    private func computeIsNonSchoolDay(_ day: Date) -> Bool {
        // 1) Explicit non-school day wins
        if nonSchoolDays?.contains(day) == true {
            return true
        }

        // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
        let weekday = AppCalendar.shared.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)

        if !isWeekend {
            return false
        }

        // 3) Weekend override makes it a school day
        if schoolDayOverrides?.contains(day) == true {
            return false
        }

        return true
    }
}
