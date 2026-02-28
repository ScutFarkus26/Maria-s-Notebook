//
//  UnlockNextLessonService.swift
//  Maria's Notebook
//
//  Service for unlocking the next lesson in a sequence for specific students.
//  Handles finding the next lesson and marking it as manually unblocked.
//

import Foundation
import SwiftData
import OSLog

/// Service for manually unlocking next lessons when students are ready to progress
@MainActor
struct UnlockNextLessonService {
    private static let logger = Logger.lessons

    // MARK: - Result Type
    
    enum UnlockResult {
        case success(LessonAssignment)
        case noNextLesson
        case alreadyUnlocked
        case noCurrentLesson
        case error(String)
    }
    
    // MARK: - Unlock Logic
    
    /// Unlocks the next lesson for specific students by finding the next lesson in sequence
    /// and marking it as manually unblocked if it exists in the inbox
    /// - Parameters:
    ///   - currentLessonID: The lesson ID the students just completed
    ///   - studentIDs: The students ready to progress
    ///   - modelContext: SwiftData context
    ///   - lessons: All available lessons
    ///   - lessonAssignments: All LessonAssignments
    /// - Returns: UnlockResult indicating success or reason for failure
    static func unlockNextLesson(
        after currentLessonID: UUID,
        for studentIDs: Set<UUID>,
        modelContext: ModelContext,
        lessons: [Lesson],
        lessonAssignments: [LessonAssignment]
    ) -> UnlockResult {
        // Find the current lesson
        guard let currentLesson = lessons.first(where: { $0.id == currentLessonID }) else {
            return .noCurrentLesson
        }
        
        // Find the next lesson in sequence
        guard let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: lessons) else {
            return .noNextLesson
        }
        
        // Check if a LessonAssignment already exists for this lesson + students combo
        // Look for unscheduled, ungiven lessons (in the inbox)
        let existingLessonAssignment = lessonAssignments.first { la in
            la.lessonIDUUID == nextLesson.id &&
            Set(la.studentUUIDs) == studentIDs &&
            la.presentedAt == nil &&
            la.scheduledFor == nil
        }
        
        if let existing = existingLessonAssignment {
            // Already exists - just mark as unblocked
            if existing.manuallyUnblocked {
                return .alreadyUnlocked
            }
            
            existing.manuallyUnblocked = true
            safeSave(modelContext: modelContext, context: "unlockNextLesson")
            return .success(existing)
        }
        
        // Doesn't exist yet - create it
        let lessonAssignment = PresentationFactory.makeDraft(
            lessonID: nextLesson.id,
            studentIDs: Array(studentIDs)
        )
        lessonAssignment.manuallyUnblocked = true
        modelContext.insert(lessonAssignment)
        safeSave(modelContext: modelContext, context: "unlockNextLesson")
        return .success(lessonAssignment)
    }
    
    /// Convenience method to unlock for a single student
    static func unlockNextLesson(
        after currentLessonID: UUID,
        for studentID: UUID,
        modelContext: ModelContext,
        lessons: [Lesson],
        lessonAssignments: [LessonAssignment]
    ) -> UnlockResult {
        unlockNextLesson(
            after: currentLessonID,
            for: [studentID],
            modelContext: modelContext,
            lessons: lessons,
            lessonAssignments: lessonAssignments
        )
    }
    
    /// Gets the name of the next lesson (for UI display)
    static func getNextLessonName(
        after currentLessonID: UUID,
        lessons: [Lesson]
    ) -> String? {
        guard let currentLesson = lessons.first(where: { $0.id == currentLessonID }),
              let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: lessons) else {
            return nil
        }
        return nextLesson.name
    }

    // MARK: - Helper Methods

    private static func safeSave(modelContext: ModelContext, context: String = #function) {
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save in \(context, privacy: .public): \(error, privacy: .public)")
        }
    }
}
