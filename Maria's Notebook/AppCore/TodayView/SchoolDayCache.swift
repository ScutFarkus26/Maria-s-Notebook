// SchoolDayCache.swift
// Helper class to cache school day data for TodayView
// This avoids repeated database fetches when iterating through dates

import Foundation
import CoreData

/// Helper class to cache school day data for TodayView
/// This avoids repeated database fetches when iterating through dates
class SchoolDayCache {
    var cachedNonSchoolDays: Set<Date> = []
    var cachedSchoolDayOverrides: Set<Date> = []
    var cachedYearRange: ClosedRange<Int>?

    func cacheSchoolDayData(for date: Date, viewContext: NSManagedObjectContext) {
        let cal = AppCalendar.shared
        let year = cal.component(.year, from: date)
        let yearRange = (year - 1)...(year + 1)

        // Check if we already have cached data for this year range
        if let cachedRange = cachedYearRange,
           cachedRange.contains(year) {
            return // Cache is still valid
        }

        // Calculate date range for 2-year window (1 year before to 1 year after)
        guard let startDate = cal.date(from: DateComponents(year: year - 1, month: 1, day: 1)),
              let endDate = cal.date(from: DateComponents(year: year + 2, month: 1, day: 1)) else {
            return
        }

        let startOfWindow = AppCalendar.startOfDay(startDate)
        let endOfWindow = AppCalendar.startOfDay(endDate)

        // Fetch all NonSchoolDay records in the window
        do {
            let fetchRequest: NSFetchRequest<CDNonSchoolDay> = CDFetchRequest(CDNonSchoolDay.self)
            fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfWindow as NSDate, endOfWindow as NSDate)
            let nonSchoolDays = try viewContext.fetch(fetchRequest)
            cachedNonSchoolDays = Set(nonSchoolDays.compactMap { $0.date.map { AppCalendar.startOfDay($0) } })
        } catch {
            cachedNonSchoolDays = []
        }

        // Fetch all SchoolDayOverride records in the window
        do {
            let fetchRequest: NSFetchRequest<CDSchoolDayOverride> = CDFetchRequest(CDSchoolDayOverride.self)
            fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date < %@", startOfWindow as NSDate, endOfWindow as NSDate)
            let overrides = try viewContext.fetch(fetchRequest)
            cachedSchoolDayOverrides = Set(overrides.compactMap { $0.date.map { AppCalendar.startOfDay($0) } })
        } catch {
            cachedSchoolDayOverrides = []
        }

        cachedYearRange = yearRange
    }

    func isNonSchoolDay(_ date: Date) -> Bool {
        let day = AppCalendar.startOfDay(date)
        let cal = AppCalendar.shared

        // 1) Explicit non-school day wins (check cache)
        if cachedNonSchoolDays.contains(day) {
            return true
        }

        // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
        let weekday = cal.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }

        // 3) Weekend override makes it a school day (check cache)
        if cachedSchoolDayOverrides.contains(day) {
            return false
        }

        return true
    }
}
