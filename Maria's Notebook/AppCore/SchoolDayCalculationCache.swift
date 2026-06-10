import Foundation
import CoreData
import OSLog

/// Thread-safe cache for school day calculations to avoid repeated database queries during rendering
@MainActor
final class SchoolDayCalculationCache {
    static let shared = SchoolDayCalculationCache()
    
    private struct CacheKey: Hashable {
        let startDate: Date
        let endDate: Date
    }
    
    private var cache: [CacheKey: Int] = [:]
    private var nonSchoolDaysCache: Set<Date> = []
    private var lastCacheRefresh: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    /// Clear the cache (call when school calendar data changes)
    func invalidate() {
        cache.removeAll()
        nonSchoolDaysCache.removeAll()
        lastCacheRefresh = nil
    }
    
    /// Preload non-school days for a date range to enable fast lookups.
    /// The set itself is built by `SchoolDayChecker` (the canonical rules);
    /// this class only contributes the caching.
    func preloadNonSchoolDays(
        from start: Date,
        to end: Date,
        using context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) {
        // Check if cache needs refresh
        if let lastRefresh = lastCacheRefresh, Date().timeIntervalSince(lastRefresh) < cacheValidityDuration {
            return // Cache is still valid
        }

        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) else { return }

        nonSchoolDaysCache = SchoolDayChecker.nonSchoolDaySet(
            in: startDay..<endExclusive,
            using: context,
            calendar: calendar
        )
        lastCacheRefresh = Date()
    }
    
    /// Calculate school days between two dates using cached data
    /// Returns cached result if available, otherwise computes and caches
    func schoolDaysBetween(
        start: Date,
        end: Date,
        using context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        
        if endDay <= startDay { return 0 }
        
        let key = CacheKey(startDate: startDay, endDate: endDay)
        
        // Return cached result if available
        if let cached = cache[key] {
            return cached
        }
        
        // Ensure cache is preloaded
        preloadNonSchoolDays(from: startDay, to: endDay, using: context, calendar: calendar)
        
        // Calculate school days using cached non-school days
        var count = 0
        var cursor = startDay
        var iterations = 0
        let maxIterations = 10000 // ~27 years of days
        while cursor < endDay && iterations < maxIterations {
            iterations += 1
            if !nonSchoolDaysCache.contains(cursor) {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor else { break }
            cursor = next
        }
        
        let result = max(0, count)
        cache[key] = result
        return result
    }
    
    /// Convenience method matching the existing API
    func schoolDaysSinceCreation(
        createdAt: Date,
        asOf today: Date = Date(),
        using context: NSManagedObjectContext,
        calendar: Calendar = .current
    ) -> Int {
        return schoolDaysBetween(start: createdAt, end: today, using: context, calendar: calendar)
    }
}
