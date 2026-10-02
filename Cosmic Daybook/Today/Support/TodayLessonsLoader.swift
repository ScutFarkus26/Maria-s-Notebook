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

    // MARK: - Lesson Plans

    /// The lessons among `lessons` that have a plan to open (the lesson
    /// rows' document button). Asked once per reload: deciding walks the
    /// lesson's attachments, which the rows used to do on every draw.
    static func lessonIDsWithPlan(
        for lessons: [CDLessonAssignment],
        lessonsByID: [UUID: CDLesson]
    ) -> Set<UUID> {
        var result = Set<UUID>()
        for lessonID in Set(lessons.map(\.resolvedLessonID)) {
            if let lesson = lessonsByID[lessonID], hasPlanDocument(lesson) {
                result.insert(lessonID)
            }
        }
        return result
    }

    /// A primary attachment, or a Pages file by path or bookmark.
    static func hasPlanDocument(_ lesson: CDLesson) -> Bool {
        if let primaryID = lesson.primaryAttachmentIDUUID,
           LessonFileStorage.getAttachments(forLesson: lesson).contains(where: { $0.id == primaryID }) {
            return true
        }
        if let relativePath = lesson.pagesFileRelativePath, !relativePath.isEmpty {
            return true
        }
        return lesson.pagesFileBookmark != nil
    }
}
