// TodayLessonsLoader.swift
// Loader for processing lesson data for the Today view.
// Encapsulates the lesson loading and filtering logic used by TodayViewModel.

import Foundation
import CoreData

// MARK: - Today Lessons Loader

/// Loader for processing lessons for the Today view.
enum TodayLessonsLoader {

    // MARK: - Types

    /// Result of loading lessons for a day.
    struct LessonsResult {
        let lessons: [CDLessonAssignment]
        let neededStudentIDs: Set<UUID>
        let neededLessonIDs: Set<UUID>
    }

    // MARK: - Load Lessons

    /// Fetches and collects IDs for lessons on a given day.
    /// - Parameters:
    ///   - day: Start of the day
    ///   - nextDay: Start of the next day
    ///   - context: Model context for fetching
    /// - Returns: Lessons and the IDs needed for caching
    static func fetchLessonsWithIDs(
        day: Date,
        nextDay: Date,
        context: NSManagedObjectContext,
        errorCollector: FetchErrorCollector? = nil
    ) -> LessonsResult {
        let dayLessons = TodayDataFetcher.fetchLessons(
            day: day, nextDay: nextDay, context: context, errorCollector: errorCollector
        )

        if dayLessons.isEmpty {
            return LessonsResult(lessons: [], neededStudentIDs: [], neededLessonIDs: [])
        }

        // Collect IDs from today's lessons
        var neededStudentIDs = Set<UUID>()
        var neededLessonIDs = Set<UUID>()

        for sl in dayLessons {
            neededStudentIDs.formUnion(sl.resolvedStudentIDs)
            neededLessonIDs.insert(sl.resolvedLessonID)
        }

        return LessonsResult(
            lessons: dayLessons,
            neededStudentIDs: neededStudentIDs,
            neededLessonIDs: neededLessonIDs
        )
    }
}
