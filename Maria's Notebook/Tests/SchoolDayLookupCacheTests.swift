#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Preload Tests

@Suite("SchoolDayLookupCache Preload Tests", .serialized)
@MainActor
struct SchoolDayLookupCachePreloadTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            NonSchoolDay.self,
            SchoolDayOverride.self,
        ])
    }

    @Test("isPreloaded returns false before preload")
    func isPreloadedReturnsFalseBeforePreload() throws {
        let cache = SchoolDayLookupCache()

        #expect(cache.isPreloaded == false)
    }

    @Test("isPreloaded returns true after preload")
    func isPreloadedReturnsTrueAfterPreload() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cache = SchoolDayLookupCache()

        cache.preload(using: context)

        #expect(cache.isPreloaded == true)
    }

    @Test("invalidate clears preloaded state")
    func invalidateClearsPreloadedState() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cache = SchoolDayLookupCache()

        cache.preload(using: context)
        #expect(cache.isPreloaded == true)

        cache.invalidate()

        #expect(cache.isPreloaded == false)
    }
}

// MARK: - Non-School Day Tests

@Suite("SchoolDayLookupCache Non-School Day Tests", .serialized)
@MainActor
struct SchoolDayLookupCacheNonSchoolDayTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            NonSchoolDay.self,
            SchoolDayOverride.self,
        ])
    }

    @Test("weekends are non-school days by default")
    func weekendsAreNonSchoolDaysByDefault() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        // Find a Saturday (weekday == 7) and Sunday (weekday == 1)
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 18 // Saturday, Jan 18, 2025
        let saturday = calendar.date(from: components)!

        components.day = 19 // Sunday, Jan 19, 2025
        let sunday = calendar.date(from: components)!

        #expect(cache.isNonSchoolDay(saturday) == true)
        #expect(cache.isNonSchoolDay(sunday) == true)
    }

    @Test("weekdays are school days by default")
    func weekdaysAreSchoolDaysByDefault() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        // Monday, Jan 20, 2025
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 20
        let monday = calendar.date(from: components)!

        #expect(cache.isNonSchoolDay(monday) == false)
        #expect(cache.isSchoolDay(monday) == true)
    }

    @Test("explicit non-school day overrides weekday")
    func explicitNonSchoolDayOverridesWeekday() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Monday, Jan 20, 2025
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 20
        let monday = calendar.date(from: components)!

        // Add as non-school day (holiday)
        let nonSchoolDay = NonSchoolDay(date: monday, reason: "Holiday")
        context.insert(nonSchoolDay)
        try context.save()

        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        #expect(cache.isNonSchoolDay(monday) == true)
    }

    @Test("school day override makes weekend a school day")
    func schoolDayOverrideMakesWeekendSchoolDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Saturday, Jan 18, 2025
        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 18
        let saturday = calendar.date(from: components)!

        // Add override to make Saturday a school day
        let override = SchoolDayOverride(date: saturday)
        context.insert(override)
        try context.save()

        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        #expect(cache.isNonSchoolDay(saturday) == false)
        #expect(cache.isSchoolDay(saturday) == true)
    }

    @Test("isSchoolDay is inverse of isNonSchoolDay")
    func isSchoolDayIsInverse() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 20 // Monday
        let monday = calendar.date(from: components)!

        components.day = 18 // Saturday
        let saturday = calendar.date(from: components)!

        #expect(cache.isSchoolDay(monday) == !cache.isNonSchoolDay(monday))
        #expect(cache.isSchoolDay(saturday) == !cache.isNonSchoolDay(saturday))
    }
}

// MARK: - School Days Between Tests

@Suite("SchoolDayLookupCache School Days Between Tests", .serialized)
@MainActor
struct SchoolDayLookupCacheSchoolDaysBetweenTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            NonSchoolDay.self,
            SchoolDayOverride.self,
        ])
    }

    @Test("schoolDaysBetween returns zero for same day")
    func schoolDaysBetweenReturnsZeroForSameDay() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 20
        let monday = calendar.date(from: components)!

        let count = cache.schoolDaysBetween(start: monday, end: monday)

        #expect(count == 0)
    }

    @Test("schoolDaysBetween counts weekdays correctly")
    func schoolDaysBetweenCountsWeekdaysCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 20 // Monday
        let monday = calendar.date(from: components)!

        components.day = 25 // Saturday (end date exclusive)
        let saturday = calendar.date(from: components)!

        // Mon, Tue, Wed, Thu, Fri = 5 school days
        let count = cache.schoolDaysBetween(start: monday, end: saturday)

        #expect(count == 5)
    }

    @Test("schoolDaysBetween excludes weekends")
    func schoolDaysBetweenExcludesWeekends() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 20 // Monday
        let monday = calendar.date(from: components)!

        components.day = 27 // Following Monday (end date exclusive)
        let nextMonday = calendar.date(from: components)!

        // Mon-Fri = 5 school days, weekend skipped
        let count = cache.schoolDaysBetween(start: monday, end: nextMonday)

        #expect(count == 5)
    }

    @Test("schoolDaysBetween respects non-school days")
    func schoolDaysBetweenRespectsNonSchoolDays() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 20 // Monday
        let monday = calendar.date(from: components)!

        components.day = 22 // Wednesday
        let wednesday = calendar.date(from: components)!

        // Make Wednesday a non-school day
        let nonSchoolDay = NonSchoolDay(date: wednesday, reason: "Holiday")
        context.insert(nonSchoolDay)
        try context.save()

        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        components.day = 25 // Saturday (end date exclusive)
        let saturday = calendar.date(from: components)!

        // Mon, Tue, (Wed holiday), Thu, Fri = 4 school days
        let count = cache.schoolDaysBetween(start: monday, end: saturday)

        #expect(count == 4)
    }

    @Test("schoolDaysBetween returns zero when end before start")
    func schoolDaysBetweenReturnsZeroWhenEndBeforeStart() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 25
        let laterDate = calendar.date(from: components)!

        components.day = 20
        let earlierDate = calendar.date(from: components)!

        let count = cache.schoolDaysBetween(start: laterDate, end: earlierDate)

        #expect(count == 0)
    }
}

// MARK: - Caching Tests

@Suite("SchoolDayLookupCache Caching Tests", .serialized)
@MainActor
struct SchoolDayLookupCacheCachingTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            NonSchoolDay.self,
            SchoolDayOverride.self,
        ])
    }

    @Test("memoization returns consistent results")
    func memoizationReturnsConsistentResults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 20
        let monday = calendar.date(from: components)!

        // Call multiple times to test memoization
        let result1 = cache.isNonSchoolDay(monday)
        let result2 = cache.isNonSchoolDay(monday)
        let result3 = cache.isNonSchoolDay(monday)

        #expect(result1 == result2)
        #expect(result2 == result3)
        #expect(result1 == false) // Monday is a school day
    }

    @Test("invalidate clears memoization cache")
    func invalidateClearsMemoizationCache() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let calendar = Calendar.current
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 20
        let monday = calendar.date(from: components)!

        let cache = SchoolDayLookupCache()
        cache.preload(using: context)

        // First call - should be school day
        let beforeResult = cache.isNonSchoolDay(monday)
        #expect(beforeResult == false)

        // Add non-school day and invalidate
        let nonSchoolDay = NonSchoolDay(date: monday, reason: "Holiday")
        context.insert(nonSchoolDay)
        try context.save()

        cache.invalidate()
        cache.preload(using: context)

        // After invalidate and reload - should now be non-school day
        let afterResult = cache.isNonSchoolDay(monday)
        #expect(afterResult == true)
    }
}

#endif
