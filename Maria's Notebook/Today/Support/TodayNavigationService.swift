// TodayNavigationService.swift
// Service for navigating between school days and finding days with lessons.
// Encapsulates school day calculation logic used by TodayViewModel.

import Foundation
import CoreData

// MARK: - Today Navigation Service

/// Service for finding school days and days with lessons.
/// School-day checks go through `SchoolCalendarService`'s shared cache.
enum TodayNavigationService {

    // MARK: - CDLesson Navigation

    /// Finds the next day (after the given date) that has lessons scheduled.
    /// Only considers school days and respects the given level filter.
    /// - Parameters:
    ///   - date: The reference date
    ///   - levelFilter: Level filter to apply
    ///   - context: Managed object context for fetching data
    /// - Returns: The next day with lessons, or the next school day if none found
    static func nextDayWithLessons(
        after date: Date,
        levelFilter: LevelFilter,
        context: NSManagedObjectContext
    ) -> Date {
        let calendar = SchoolCalendarService.shared
        var current = calendar.nextSchoolDaySync(after: date, using: context)
        // Safety cap: search up to 2 years forward
        for _ in 0..<730 {
            if hasLessonsMatching(on: current, levelFilter: levelFilter, context: context) {
                return current
            }
            current = calendar.nextSchoolDaySync(after: current, using: context)
            // Prevent infinite loop if we've wrapped around
            if current <= date {
                break
            }
        }
        // If no day with lessons found, return the next school day
        return calendar.nextSchoolDaySync(after: date, using: context)
    }

    /// Finds the previous day (before the given date) that has lessons scheduled.
    /// Only considers school days and respects the given level filter.
    /// - Parameters:
    ///   - date: The reference date
    ///   - levelFilter: Level filter to apply
    ///   - context: Managed object context for fetching data
    /// - Returns: The previous day with lessons, or the previous school day if none found
    static func previousDayWithLessons(
        before date: Date,
        levelFilter: LevelFilter,
        context: NSManagedObjectContext
    ) -> Date {
        let calendar = SchoolCalendarService.shared
        var current = calendar.previousSchoolDaySync(before: date, using: context)
        // Safety cap: search up to 2 years backward
        for _ in 0..<730 {
            if hasLessonsMatching(on: current, levelFilter: levelFilter, context: context) {
                return current
            }
            let prev = calendar.previousSchoolDaySync(before: current, using: context)
            // Prevent infinite loop if we've wrapped around
            if prev >= date || prev == current {
                break
            }
            current = prev
        }
        // If no day with lessons found, return the previous school day
        return calendar.previousSchoolDaySync(before: date, using: context)
    }

    // MARK: - Private Helpers

    /// Checks if a day has lessons matching the level filter.
    private static func hasLessonsMatching(
        on date: Date,
        levelFilter: LevelFilter,
        context: NSManagedObjectContext
    ) -> Bool {
        let (day, nextDay) = AppCalendar.dayRange(for: date)
        do {
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(
                format: "scheduledFor >= %@ AND scheduledFor < %@",
                day as NSDate, nextDay as NSDate
            )
            let lessons = try context.fetch(request)
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

            // NOTE: Core Data NSPredicate doesn't efficiently support IN queries with large UUID sets,
            // so we fetch all and filter in memory
            if !neededStudentIDs.isEmpty {
                let studentRequest = CDFetchRequest(CDStudent.self)
                studentRequest.fetchLimit = 500 // Safety limit for student roster
                let allStudents = try context.fetch(studentRequest).filterEnrolled()
                let filtered = allStudents.filter { student in
                    guard let studentID = student.id else { return false }
                    return neededStudentIDs.contains(studentID)
                }
                // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
                let visibleStudents = TestStudentsFilter.filterVisible(filtered).uniqueByID
                let studentsByID = Dictionary(
                    visibleStudents.compactMap { student -> (UUID, CDStudent)? in
                        guard let studentID = student.id else { return nil }
                        return (studentID, student)
                    },
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
        _ lessons: [CDLessonAssignment],
        studentsByID: [UUID: CDStudent],
        levelFilter: LevelFilter
    ) -> [CDLessonAssignment] {
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
