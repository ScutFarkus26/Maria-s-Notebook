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
        cdAssignments: [CDLessonAssignment],
        saveImmediately: Bool = true
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

        // Reuse any assignment for this lesson that already covers all of these
        // students and hasn't been presented — an exact inbox draft, a group draft,
        // or a scheduled presentation. Creating a fresh draft alongside any of those
        // would duplicate the presentation. Prefer the exact unscheduled match so a
        // solo unlock keeps its own inbox draft when both exist.
        let coveringAssignments = cdAssignments.filter { la in
            la.lessonID == nextLessonIDString &&
            la.presentedAt == nil &&
            studentIDs.isSubset(of: Set(la.studentUUIDs))
        }
        let existingAssignment = coveringAssignments.first { la in
            Set(la.studentUUIDs) == studentIDs && la.scheduledFor == nil
        } ?? coveringAssignments.first

        if let existing = existingAssignment {
            if existing.manuallyUnblocked {
                return .alreadyUnlocked
            }

            existing.manuallyUnblocked = true
            if saveImmediately {
                context.safeSave()
            }
            return .success(existing)
        }

        // Doesn't exist yet - create it
        let newAssignment = PresentationFactory.makeDraft(
            lessonID: nextLessonID,
            studentIDs: Array(studentIDs),
            context: context
        )
        newAssignment.manuallyUnblocked = true
        if saveImmediately {
            context.safeSave()
        }
        return .success(newAssignment)
    }

    /// Convenience method to unlock for a single student
    static func unlockNextLesson(
        after currentLessonID: UUID,
        for studentID: UUID,
        context: NSManagedObjectContext,
        lessons: [CDLesson],
        cdAssignments: [CDLessonAssignment],
        saveImmediately: Bool = true
    ) -> UnlockResult {
        unlockNextLesson(
            after: currentLessonID,
            for: [studentID],
            context: context,
            lessons: lessons,
            cdAssignments: cdAssignments,
            saveImmediately: saveImmediately
        )
    }

    // MARK: - Deprecated SwiftData Overloads

    // Deprecated SwiftData bridge methods removed - no longer needed with Core Data.

}
