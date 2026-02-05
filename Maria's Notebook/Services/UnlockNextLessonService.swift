//
//  UnlockNextLessonService.swift
//  Maria's Notebook
//
//  Service for unlocking the next lesson in a sequence for specific students.
//  Handles finding the next lesson and marking it as manually unblocked.
//

import Foundation
import SwiftData

/// Service for manually unlocking next lessons when students are ready to progress
@MainActor
struct UnlockNextLessonService {
    
    // MARK: - Result Type
    
    enum UnlockResult {
        case success(StudentLesson)
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
    ///   - studentLessons: All StudentLessons
    /// - Returns: UnlockResult indicating success or reason for failure
    static func unlockNextLesson(
        after currentLessonID: UUID,
        for studentIDs: Set<UUID>,
        modelContext: ModelContext,
        lessons: [Lesson],
        studentLessons: [StudentLesson]
    ) -> UnlockResult {
        // Find the current lesson
        guard let currentLesson = lessons.first(where: { $0.id == currentLessonID }) else {
            return .noCurrentLesson
        }
        
        // Find the next lesson in sequence
        guard let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: lessons) else {
            return .noNextLesson
        }
        
        // Check if a StudentLesson already exists for this lesson + students combo
        // Look for unscheduled, ungiven lessons (in the inbox)
        let existingStudentLesson = studentLessons.first { sl in
            sl.resolvedLessonID == nextLesson.id &&
            Set(sl.resolvedStudentIDs) == studentIDs &&
            sl.givenAt == nil &&
            sl.scheduledFor == nil
        }
        
        if let existing = existingStudentLesson {
            // Already exists - just mark as unblocked
            if existing.manuallyUnblocked {
                return .alreadyUnlocked
            }
            
            existing.manuallyUnblocked = true
            try? modelContext.save()
            return .success(existing)
        }
        
        // Doesn't exist yet - create it and mark as unblocked
        let newStudentLesson = StudentLesson(
            lessonID: nextLesson.id,
            studentIDs: Array(studentIDs),
            manuallyUnblocked: true
        )
        
        modelContext.insert(newStudentLesson)
        try? modelContext.save()
        
        return .success(newStudentLesson)
    }
    
    /// Convenience method to unlock for a single student
    static func unlockNextLesson(
        after currentLessonID: UUID,
        for studentID: UUID,
        modelContext: ModelContext,
        lessons: [Lesson],
        studentLessons: [StudentLesson]
    ) -> UnlockResult {
        unlockNextLesson(
            after: currentLessonID,
            for: [studentID],
            modelContext: modelContext,
            lessons: lessons,
            studentLessons: studentLessons
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
}
