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
    /// The day range currently covered by `nonSchoolDaysCache` (start ..< end-exclusive).
    private var cachedRange: Range<Date>?
    private var lastCacheRefresh: Date?
    private let cacheValidityDuration: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    /// Clear the cache (call when school calendar data changes)
    func invalidate() {
        cache.removeAll()
        nonSchoolDaysCache.removeAll()
        cachedRange = nil
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
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        guard let endExclusive = calendar.date(byAdding: .day, value: 1, to: endDay) else { return }
        let requested = startDay..<endExclusive

        // Reuse the cache only if it is fresh AND already covers the requested range.
        // A time-only check would reuse a set loaded for a *different* range, counting
        // weekends/holidays outside the loaded window as school days.
        let isFresh = lastCacheRefresh.map { Date().timeIntervalSince($0) < cacheValidityDuration } ?? false
        if isFresh, let cached = cachedRange,
           cached.lowerBound <= requested.lowerBound, requested.upperBound <= cached.upperBound {
            return // Fresh and fully covers the requested range
        }

        // Load a window covering both the requested range and any still-fresh cached range,
        // so coverage never shrinks within the validity window.
        var loadRange = requested
        if isFresh, let cached = cachedRange {
            loadRange = min(cached.lowerBound, requested.lowerBound)
                ..< max(cached.upperBound, requested.upperBound)
        }

        nonSchoolDaysCache = SchoolDayChecker.nonSchoolDaySet(
            in: loadRange,
            using: context,
            calendar: calendar
        )
        cachedRange = loadRange
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
