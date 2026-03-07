//
//  PlanNextLessonService.swift
//  Maria's Notebook
//
//  Unified service for planning the next lesson in a group/subject sequence.
//  Consolidates duplicate logic from PlanningWeekViewContent, PlanningActions,
//  and PresentationDetailActions to ensure consistent behavior.
//

import Foundation
import SwiftData

/// Service for finding and creating the next lesson in a subject/group sequence.
/// Ensures consistent duplicate checking and creation logic across all entry points.
@MainActor
struct PlanNextLessonService {

    // MARK: - Result Type

    enum PlanResult {
        case success(LessonAssignment)
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

    /// Checks if a LessonAssignment already exists for the given lesson and students.
    /// Uses consistent criteria: same lesson ID, same students, and not yet given (presentedAt == nil)
    /// AND not yet scheduled (scheduledFor == nil) - i.e., would be in the inbox.
    /// - Parameters:
    ///   - lessonID: The lesson ID to check
    ///   - studentIDs: The set of student IDs to check
    ///   - existingLessonAssignments: All LessonAssignments to search through
    /// - Returns: true if a matching unscheduled, unpresented LessonAssignment exists
    static func existsInInbox(
        lessonID: UUID,
        studentIDs: Set<UUID>,
        in existingLessonAssignments: [LessonAssignment]
    ) -> Bool {
        existingLessonAssignments.contains { la in
            la.lessonIDUUID == lessonID &&
            Set(la.studentUUIDs) == studentIDs &&
            la.presentedAt == nil &&
            la.scheduledFor == nil
        }
    }

    /// Checks if a LessonAssignment already exists that hasn't been given yet.
    /// This is a less strict check - the lesson may be scheduled but not yet presented.
    /// - Parameters:
    ///   - lessonID: The lesson ID to check
    ///   - studentIDs: The set of student IDs to check
    ///   - existingLessonAssignments: All LessonAssignments to search through
    /// - Returns: true if a matching unpresented LessonAssignment exists (scheduled or not)
    static func existsActive(
        lessonID: UUID,
        studentIDs: Set<UUID>,
        in existingLessonAssignments: [LessonAssignment]
    ) -> Bool {
        existingLessonAssignments.contains { la in
            la.lessonIDUUID == lessonID &&
            Set(la.studentUUIDs) == studentIDs &&
            la.presentedAt == nil
        }
    }

    // MARK: - Plan Next Lesson (Main Entry Point)

    /// Plans the next lesson in the sequence for the given LessonAssignment.
    /// This is the main entry point that should be used by all UI components.
    /// - Parameters:
    ///   - lessonAssignment: The current LessonAssignment to plan the next lesson after
    ///   - allLessons: All available lessons
    ///   - allStudents: All available students
    ///   - existingLessonAssignments: All existing LessonAssignments for duplicate checking
    ///   - context: The ModelContext for inserting the new LessonAssignment
    /// - Returns: A PlanResult indicating success or the reason for failure
    @discardableResult
    static func planNextLesson(
        for lessonAssignment: LessonAssignment,
        allLessons: [Lesson],
        allStudents: [Student],
        existingLessonAssignments: [LessonAssignment],
        context: ModelContext
    ) -> PlanResult {
        // Get the current lesson
        guard let lessonIDUUID = lessonAssignment.lessonIDUUID,
              let currentLesson = allLessons.first(where: { $0.id == lessonIDUUID }) else {
            return .noCurrentLesson
        }

        // Find the next lesson in the sequence
        guard let nextLesson = findNextLesson(after: currentLesson, in: allLessons) else {
            return .noNextLesson
        }

        // Get the student IDs
        let studentIDs = Set(lessonAssignment.studentUUIDs)
        guard !studentIDs.isEmpty else {
            return .noStudents
        }

        // Check if it already exists (using strict inbox check)
        if existsInInbox(lessonID: nextLesson.id, studentIDs: studentIDs, in: existingLessonAssignments) {
            return .alreadyExists
        }

        // Create the new LessonAssignment
        let newLessonAssignment = PresentationFactory.makeDraft(
            lessonID: nextLesson.id,
            studentIDs: Array(studentIDs)
        )
        let relatedStudents = allStudents.filter { studentIDs.contains($0.id) }
        PresentationFactory.attachRelationships(
            to: newLessonAssignment,
            lesson: nextLesson,
            students: relatedStudents
        )
        context.insert(newLessonAssignment)
        return .success(newLessonAssignment)
    }

    /// Plans the next lesson when you already know what the next lesson is.
    /// Used when the caller has already determined the next lesson (e.g., from UI state).
    /// - Parameters:
    ///   - nextLesson: The lesson to create a LessonAssignment for
    ///   - studentIDs: The students to include
    ///   - allStudents: All available students (for relationship attachment)
    ///   - allLessons: All available lessons (for relationship attachment)
    ///   - existingLessonAssignments: All existing LessonAssignments for duplicate checking
    ///   - context: The ModelContext for inserting the new LessonAssignment
    /// - Returns: A PlanResult indicating success or the reason for failure
    @discardableResult
    // swiftlint:disable:next function_parameter_count
    static func planLesson(
        _ nextLesson: Lesson,
        forStudents studentIDs: Set<UUID>,
        allStudents: [Student],
        allLessons: [Lesson],
        existingLessonAssignments: [LessonAssignment],
        context: ModelContext
    ) -> PlanResult {
        guard !studentIDs.isEmpty else {
            return .noStudents
        }

        // Check if it already exists
        if existsInInbox(lessonID: nextLesson.id, studentIDs: studentIDs, in: existingLessonAssignments) {
            return .alreadyExists
        }

        // Create the new LessonAssignment
        let newLessonAssignment = PresentationFactory.makeDraft(
            lessonID: nextLesson.id,
            studentIDs: Array(studentIDs)
        )
        let relatedStudents = allStudents.filter { studentIDs.contains($0.id) }
        PresentationFactory.attachRelationships(
            to: newLessonAssignment,
            lesson: allLessons.first(where: { $0.id == nextLesson.id }),
            students: relatedStudents
        )
        context.insert(newLessonAssignment)
        return .success(newLessonAssignment)
    }
}
