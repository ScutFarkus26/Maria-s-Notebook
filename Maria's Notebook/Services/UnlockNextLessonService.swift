//
//  UnlockNextLessonService.swift
//  Maria's Notebook
//
//  Service for unlocking the next lesson in a sequence for specific students.
//  Handles finding the next lesson and marking it as manually unblocked.
//

import Foundation
import CoreData
import OSLog

/// Service for manually unlocking next lessons when students are ready to progress
@MainActor
struct UnlockNextLessonService {
    private static let logger = Logger.lessons

    // MARK: - Result Type

    enum UnlockResult {
        case success(CDLessonAssignment)
        case noNextLesson
        case alreadyUnlocked
        case noCurrentLesson
        case error(String)

    }

    // MARK: - Core Data Unlock Logic

    /// Unlocks the next lesson for specific students by finding the next lesson in sequence
    /// and marking it as manually unblocked if it exists in the inbox
    /// - Parameters:
    ///   - currentLessonID: The lesson ID the students just completed
    ///   - studentIDs: The students ready to progress
    ///   - context: Core Data managed object context
    ///   - lessons: All available lessons
    ///   - lessonAssignments: All LessonAssignments
    /// - Returns: UnlockResult indicating success or reason for failure
    static func unlockNextLesson(
        after currentLessonID: UUID,
        for studentIDs: Set<UUID>,
        context: NSManagedObjectContext,
        lessons: [CDLesson],
        cdAssignments: [CDLessonAssignment]
    ) -> UnlockResult {
        // Find the current lesson
        guard let currentLesson = lessons.first(where: { $0.id == currentLessonID }) else {
            return .noCurrentLesson
        }

        // Find the next lesson in sequence
        guard let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: lessons) else {
            return .noNextLesson
        }

        guard let nextLessonID = nextLesson.id else { return .noNextLesson }
        let nextLessonIDString = nextLessonID.uuidString

        // Check if a CDLessonAssignment already exists for this lesson + students combo
        // Look for unscheduled, ungiven lessons (in the inbox)
        let existingAssignment = cdAssignments.first { la in
            la.lessonID == nextLessonIDString &&
            Set(la.studentUUIDs) == studentIDs &&
            la.presentedAt == nil &&
            la.scheduledFor == nil
        }

        if let existing = existingAssignment {
            if existing.manuallyUnblocked {
                return .alreadyUnlocked
            }

            existing.manuallyUnblocked = true
            context.safeSave()
            return .success(existing)
        }

        // Doesn't exist yet - create it
        let newAssignment = PresentationFactory.makeDraft(
            lessonID: nextLessonID,
            studentIDs: Array(studentIDs),
            context: context
        )
        newAssignment.manuallyUnblocked = true
        context.safeSave()
        return .success(newAssignment)
    }

    /// Convenience method to unlock for a single student
    static func unlockNextLesson(
        after currentLessonID: UUID,
        for studentID: UUID,
        context: NSManagedObjectContext,
        lessons: [CDLesson],
        cdAssignments: [CDLessonAssignment]
    ) -> UnlockResult {
        unlockNextLesson(
            after: currentLessonID,
            for: [studentID],
            context: context,
            lessons: lessons,
            cdAssignments: cdAssignments
        )
    }

    // MARK: - Deprecated SwiftData Overloads

    // Deprecated SwiftData bridge methods removed - no longer needed with Core Data.

    /// Gets the name of the next lesson (for UI display)
    static func getNextLessonName(
        after currentLessonID: UUID,
        lessons: [CDLesson]
    ) -> String? {
        guard let currentLesson = lessons.first(where: { $0.id == currentLessonID }),
              let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: lessons) else {
            return nil
        }
        return nextLesson.name
    }
}
