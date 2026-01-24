//
//  PlanNextLessonService.swift
//  Maria's Notebook
//
//  Unified service for planning the next lesson in a group/subject sequence.
//  Consolidates duplicate logic from PlanningWeekViewContent, PlanningActions,
//  and StudentLessonDetailActions to ensure consistent behavior.
//

import Foundation
import SwiftData

/// Service for finding and creating the next lesson in a subject/group sequence.
/// Ensures consistent duplicate checking and creation logic across all entry points.
@MainActor
struct PlanNextLessonService {

    // MARK: - Result Type

    enum PlanResult {
        case success(StudentLesson)
        case alreadyExists
        case noNextLesson
        case noCurrentLesson
        case emptySubjectOrGroup
        case noStudents
    }

    // MARK: - Find Next Lesson

    /// Finds the next lesson in the same subject/group sequence.
    /// - Parameters:
    ///   - current: The current lesson to find the successor for
    ///   - allLessons: All available lessons to search through
    /// - Returns: The next lesson in the sequence, or nil if none exists
    static func findNextLesson(after current: Lesson, in allLessons: [Lesson]) -> Lesson? {
        let currentSubject = current.subject.trimmed()
        let currentGroup = current.group.trimmed()

        guard !currentSubject.isEmpty, !currentGroup.isEmpty else { return nil }

        // Find all lessons in the same subject/group, sorted by order
        let candidates = allLessons
            .filter { lesson in
                lesson.subject.trimmed().caseInsensitiveCompare(currentSubject) == .orderedSame &&
                lesson.group.trimmed().caseInsensitiveCompare(currentGroup) == .orderedSame
            }
            .sorted { $0.orderInGroup < $1.orderInGroup }

        // Find the current lesson's position and return the next one
        guard let currentIndex = candidates.firstIndex(where: { $0.id == current.id }),
              currentIndex + 1 < candidates.count else {
            return nil
        }

        return candidates[currentIndex + 1]
    }

    // MARK: - Check for Existing

    /// Checks if a StudentLesson already exists for the given lesson and students.
    /// Uses consistent criteria: same lesson ID, same students, and not yet given (givenAt == nil)
    /// AND not yet scheduled (scheduledFor == nil) - i.e., would be in the inbox.
    /// - Parameters:
    ///   - lessonID: The lesson ID to check
    ///   - studentIDs: The set of student IDs to check
    ///   - existingStudentLessons: All StudentLessons to search through
    /// - Returns: true if a matching unscheduled, ungiven StudentLesson exists
    static func existsInInbox(
        lessonID: UUID,
        studentIDs: Set<UUID>,
        in existingStudentLessons: [StudentLesson]
    ) -> Bool {
        existingStudentLessons.contains { sl in
            sl.resolvedLessonID == lessonID &&
            Set(sl.resolvedStudentIDs) == studentIDs &&
            sl.givenAt == nil &&
            sl.scheduledFor == nil
        }
    }

    /// Checks if a StudentLesson already exists that hasn't been given yet.
    /// This is a less strict check - the lesson may be scheduled but not yet presented.
    /// - Parameters:
    ///   - lessonID: The lesson ID to check
    ///   - studentIDs: The set of student IDs to check
    ///   - existingStudentLessons: All StudentLessons to search through
    /// - Returns: true if a matching ungiven StudentLesson exists (scheduled or not)
    static func existsActive(
        lessonID: UUID,
        studentIDs: Set<UUID>,
        in existingStudentLessons: [StudentLesson]
    ) -> Bool {
        existingStudentLessons.contains { sl in
            sl.resolvedLessonID == lessonID &&
            Set(sl.resolvedStudentIDs) == studentIDs &&
            sl.givenAt == nil
        }
    }

    // MARK: - Plan Next Lesson (Main Entry Point)

    /// Plans the next lesson in the sequence for the given StudentLesson.
    /// This is the main entry point that should be used by all UI components.
    /// - Parameters:
    ///   - studentLesson: The current StudentLesson to plan the next lesson after
    ///   - allLessons: All available lessons
    ///   - allStudents: All available students
    ///   - existingStudentLessons: All existing StudentLessons for duplicate checking
    ///   - context: The ModelContext for inserting the new StudentLesson
    /// - Returns: A PlanResult indicating success or the reason for failure
    @discardableResult
    static func planNextLesson(
        for studentLesson: StudentLesson,
        allLessons: [Lesson],
        allStudents: [Student],
        existingStudentLessons: [StudentLesson],
        context: ModelContext
    ) -> PlanResult {
        // Get the current lesson
        guard let lessonIDUUID = UUID(uuidString: studentLesson.lessonID),
              let currentLesson = allLessons.first(where: { $0.id == lessonIDUUID }) else {
            return .noCurrentLesson
        }

        // Find the next lesson in the sequence
        guard let nextLesson = findNextLesson(after: currentLesson, in: allLessons) else {
            return .noNextLesson
        }

        // Get the student IDs
        let studentIDs = Set(studentLesson.resolvedStudentIDs)
        guard !studentIDs.isEmpty else {
            return .noStudents
        }

        // Check if it already exists (using strict inbox check)
        if existsInInbox(lessonID: nextLesson.id, studentIDs: studentIDs, in: existingStudentLessons) {
            return .alreadyExists
        }

        // Create the new StudentLesson
        let newStudentLesson = StudentLessonFactory.makeUnscheduled(
            lessonID: nextLesson.id,
            studentIDs: Array(studentIDs)
        )

        // Attach relationships
        let relatedStudents = allStudents.filter { studentIDs.contains($0.id) }
        StudentLessonFactory.attachRelationships(
            to: newStudentLesson,
            lesson: nextLesson,
            students: relatedStudents
        )

        // Insert into context
        context.insert(newStudentLesson)

        return .success(newStudentLesson)
    }

    /// Plans the next lesson when you already know what the next lesson is.
    /// Used when the caller has already determined the next lesson (e.g., from UI state).
    /// - Parameters:
    ///   - nextLesson: The lesson to create a StudentLesson for
    ///   - studentIDs: The students to include
    ///   - allStudents: All available students (for relationship attachment)
    ///   - allLessons: All available lessons (for relationship attachment)
    ///   - existingStudentLessons: All existing StudentLessons for duplicate checking
    ///   - context: The ModelContext for inserting the new StudentLesson
    /// - Returns: A PlanResult indicating success or the reason for failure
    @discardableResult
    static func planLesson(
        _ nextLesson: Lesson,
        forStudents studentIDs: Set<UUID>,
        allStudents: [Student],
        allLessons: [Lesson],
        existingStudentLessons: [StudentLesson],
        context: ModelContext
    ) -> PlanResult {
        guard !studentIDs.isEmpty else {
            return .noStudents
        }

        // Check if it already exists
        if existsInInbox(lessonID: nextLesson.id, studentIDs: studentIDs, in: existingStudentLessons) {
            return .alreadyExists
        }

        // Create the new StudentLesson
        let newStudentLesson = StudentLessonFactory.makeUnscheduled(
            lessonID: nextLesson.id,
            studentIDs: Array(studentIDs)
        )

        // Attach relationships
        let relatedStudents = allStudents.filter { studentIDs.contains($0.id) }
        StudentLessonFactory.attachRelationships(
            to: newStudentLesson,
            lesson: allLessons.first(where: { $0.id == nextLesson.id }),
            students: relatedStudents
        )

        // Insert into context
        context.insert(newStudentLesson)

        return .success(newStudentLesson)
    }
}
