// TodayNavigationService.swift
// Service for navigating between school days and finding days with lessons.
// Encapsulates school day calculation logic used by TodayViewModel.

import Foundation
import SwiftData

// MARK: - Today Navigation Service

/// Service for finding school days and days with lessons.
/// Uses SchoolDayCache to avoid repeated database fetches.
enum TodayNavigationService {

    // MARK: - School Day Navigation

    /// Returns the next school day strictly after the given date.
    /// - Parameters:
    ///   - date: The reference date
    ///   - cache: School day cache to use (will be populated if needed)
    ///   - context: Model context for fetching school day data
    /// - Returns: The next school day after the given date
    static func nextSchoolDay(
        after date: Date,
        cache: inout SchoolDayCache,
        context: ModelContext
    ) -> Date {
        // Cache school day data once at the start to avoid repeated database fetches
        cache.cacheSchoolDayData(for: date, modelContext: context)

        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        // Start from the following day
        d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        // Safety cap to avoid infinite loops in case of data errors
        for _ in 0..<730 { // up to ~2 years
            if !cache.isNonSchoolDay(d) { return d }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    /// Returns the previous school day strictly before the given date.
    /// - Parameters:
    ///   - date: The reference date
    ///   - cache: School day cache to use (will be populated if needed)
    ///   - context: Model context for fetching school day data
    /// - Returns: The previous school day before the given date
    static func previousSchoolDay(
        before date: Date,
        cache: inout SchoolDayCache,
        context: ModelContext
    ) -> Date {
        // Cache school day data once at the start to avoid repeated database fetches
        cache.cacheSchoolDayData(for: date, modelContext: context)

        let cal = AppCalendar.shared
        var d = cal.startOfDay(for: date)
        // Start from the previous day
        d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        for _ in 0..<730 { // up to ~2 years
            if !cache.isNonSchoolDay(d) { return d }
            d = cal.date(byAdding: .day, value: -1, to: d) ?? d
        }
        return cal.startOfDay(for: date)
    }

    /// Checks if a date is a non-school day using cached data.
    /// - Parameters:
    ///   - date: The date to check
    ///   - cache: School day cache to use (will be populated if needed)
    ///   - context: Model context for fetching school day data
    /// - Returns: True if the date is a non-school day
    static func isNonSchoolDay(
        _ date: Date,
        cache: inout SchoolDayCache,
        context: ModelContext
    ) -> Bool {
        cache.cacheSchoolDayData(for: date, modelContext: context)
        return cache.isNonSchoolDay(date)
    }

    // MARK: - Lesson Navigation

    /// Finds the next day (after the given date) that has lessons scheduled.
    /// Only considers school days and respects the given level filter.
    /// - Parameters:
    ///   - date: The reference date
    ///   - levelFilter: Level filter to apply
    ///   - cache: School day cache to use
    ///   - context: Model context for fetching data
    /// - Returns: The next day with lessons, or the next school day if none found
    static func nextDayWithLessons(
        after date: Date,
        levelFilter: LevelFilter,
        cache: inout SchoolDayCache,
        context: ModelContext
    ) -> Date {
        var current = nextSchoolDay(after: date, cache: &cache, context: context)
        // Safety cap: search up to 2 years forward
        for _ in 0..<730 {
            if hasLessonsMatching(on: current, levelFilter: levelFilter, context: context) {
                return current
            }
            current = nextSchoolDay(after: current, cache: &cache, context: context)
            // Prevent infinite loop if we've wrapped around
            if current <= date {
                break
            }
        }
        // If no day with lessons found, return the next school day
        return nextSchoolDay(after: date, cache: &cache, context: context)
    }

    /// Finds the previous day (before the given date) that has lessons scheduled.
    /// Only considers school days and respects the given level filter.
    /// - Parameters:
    ///   - date: The reference date
    ///   - levelFilter: Level filter to apply
    ///   - cache: School day cache to use
    ///   - context: Model context for fetching data
    /// - Returns: The previous day with lessons, or the previous school day if none found
    static func previousDayWithLessons(
        before date: Date,
        levelFilter: LevelFilter,
        cache: inout SchoolDayCache,
        context: ModelContext
    ) -> Date {
        var current = previousSchoolDay(before: date, cache: &cache, context: context)
        // Safety cap: search up to 2 years backward
        for _ in 0..<730 {
            if hasLessonsMatching(on: current, levelFilter: levelFilter, context: context) {
                return current
            }
            let prev = previousSchoolDay(before: current, cache: &cache, context: context)
            // Prevent infinite loop if we've wrapped around
            if prev >= date || prev == current {
                break
            }
            current = prev
        }
        // If no day with lessons found, return the previous school day
        return previousSchoolDay(before: date, cache: &cache, context: context)
    }

    // MARK: - Private Helpers

    /// Checks if a day has lessons matching the level filter.
    private static func hasLessonsMatching(
        on date: Date,
        levelFilter: LevelFilter,
        context: ModelContext
    ) -> Bool {
        let (day, nextDay) = AppCalendar.dayRange(for: date)
        do {
            let descriptor = FetchDescriptor<LessonAssignment>(
                predicate: #Predicate { sl in
                    sl.scheduledForDay >= day && sl.scheduledForDay < nextDay
                }
            )
            let lessons = try context.fetch(descriptor)
            if lessons.isEmpty {
                return false
            }

            // Check if any lessons match the level filter
            var neededStudentIDs = Set<UUID>()
            for sl in lessons {
                neededStudentIDs.formUnion(sl.resolvedStudentIDs)
            }

            if neededStudentIDs.isEmpty && levelFilter == .all {
                // If no students but level filter is "all", still count it
                return true
            }

            // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
            // so we fetch all and filter in memory
            if !neededStudentIDs.isEmpty {
                var studentDescriptor = FetchDescriptor<Student>()
                studentDescriptor.fetchLimit = 500 // Safety limit for student roster
                let allStudents = try context.fetch(studentDescriptor).filter(\.isEnrolled)
                let filtered = allStudents.filter { neededStudentIDs.contains($0.id) }
                // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
                let visibleStudents = TestStudentsFilter.filterVisible(filtered).uniqueByID
                let studentsByID = Dictionary(
                    visibleStudents.map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                )

                let filteredLessons = filterLessonsByLevel(
                    lessons, studentsByID: studentsByID, levelFilter: levelFilter
                )
                return !filteredLessons.isEmpty
            }

            return false
        } catch {
            return false
        }
    }

    /// Filters lessons by level using the provided student lookup.
    private static func filterLessonsByLevel(
        _ lessons: [LessonAssignment],
        studentsByID: [UUID: Student],
        levelFilter: LevelFilter
    ) -> [LessonAssignment] {
        guard levelFilter != .all else {
            return lessons.filter { sl in
                let ids = sl.resolvedStudentIDs
                if ids.isEmpty { return true }
                return ids.contains { studentsByID[$0] != nil }
            }
        }
        return lessons.filter { sl in
            let ids = sl.resolvedStudentIDs
            if ids.isEmpty { return true }
            var anyVisible = false
            var anyVisibleMatching = false
            for sid in ids {
                if let s = studentsByID[sid] {
                    anyVisible = true
                    if levelFilter.matches(s.level) { anyVisibleMatching = true }
                }
            }
            return anyVisible && anyVisibleMatching
        }
    }
}
