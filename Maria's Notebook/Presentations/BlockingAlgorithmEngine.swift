import Foundation
import SwiftData

// MARK: - Blocking Algorithm Engine

/// Engine for calculating prerequisite blocking logic for lessons.
/// Determines which lessons are blocked by incomplete work from preceding lessons in a sequence.
enum BlockingAlgorithmEngine {

    // MARK: - Types

    /// Result of checking if a StudentLesson is blocked.
    struct BlockingCheckResult {
        let isBlocked: Bool
        let prereqOpenCount: Int
    }

    // MARK: - Blocking Check

    /// Check if a StudentLesson is blocked by incomplete prerequisite work from the preceding lesson.
    /// Uses LessonAssignment (unified model).
    ///
    /// - Parameters:
    ///   - sl: The StudentLesson to check
    ///   - lessons: All lessons (needed for group structure)
    ///   - studentLessons: All StudentLessons
    ///   - lessonAssignments: All LessonAssignments (unified model)
    ///   - workModels: All WorkModels (preferably filtered to non-complete)
    /// - Returns: A BlockingCheckResult indicating if blocked and how many prerequisites are open
    static func checkBlocking(
        for sl: StudentLesson,
        lessons: [Lesson],
        studentLessons: [StudentLesson],
        lessonAssignments: [LessonAssignment] = [],
        workModels: [WorkModel]
    ) -> BlockingCheckResult {
        // Check for manual unlock override
        if sl.manuallyUnblocked {
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
        }
        
        // Find the current lesson
        guard let currentLessonID = UUID(uuidString: sl.lessonID),
              let currentLesson = lessons.first(where: { $0.id == currentLessonID }) else {
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
        }

        // Debug logging disabled for production use
        // Set debugEnabled to true and rebuild to enable verbose blocking debug logs

        // Find the preceding lesson in the sequence (same subject/group, previous orderInGroup)
        guard let precedingLesson = findPrecedingLesson(
            currentLesson: currentLesson,
            lessons: lessons
        ) else {
            // No preceding lesson means no prerequisites to check
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
        }

        // Find the LessonAssignment for the preceding lesson with the same student group
        let studentIDs = Set(sl.resolvedStudentIDs.map { $0.uuidString })

        // Find in LessonAssignment (unified model)
        let precedingLessonAssignment = lessonAssignments.first { assignment in
            guard assignment.lessonID == precedingLesson.id.uuidString,
                  assignment.state == .presented else { return false }
            let assignmentStudentIDs = Set(assignment.studentIDs)
            return assignmentStudentIDs == studentIDs
        }

        guard let presentationID = precedingLessonAssignment?.id.uuidString else {
            // No presentation for preceding lesson means no prerequisites
            return BlockingCheckResult(isBlocked: false, prereqOpenCount: 0)
        }

        // Find WorkModel records linked to the preceding presentation
        let prerequisiteWork = workModels.filter { work in
            work.presentationID == presentationID
        }

        // Check if ANY prerequisite work is incomplete for any required student
        var prereqOpenCount = 0
        var isBlocked = false

        for work in prerequisiteWork {
            if isWorkComplete(work: work, requiredStudentIDs: sl.resolvedStudentIDs) {
                continue // This work is complete
            }

            prereqOpenCount += 1

            // Check if this work blocks any required student
            if workHasIncompleteForRequiredStudents(work: work, requiredStudentIDs: sl.resolvedStudentIDs) {
                isBlocked = true
            }
        }

        return BlockingCheckResult(isBlocked: isBlocked, prereqOpenCount: prereqOpenCount)
    }

    // MARK: - Find Preceding Lesson

    /// Find the preceding lesson in the sequence (same subject/group, previous orderInGroup).
    ///
    /// - Parameters:
    ///   - currentLesson: The lesson to find the predecessor for
    ///   - lessons: All lessons
    /// - Returns: The preceding lesson, or nil if none exists
    static func findPrecedingLesson(currentLesson: Lesson, lessons: [Lesson]) -> Lesson? {
        let currentSubject = currentLesson.subject.trimmed()
        let currentGroup = currentLesson.group.trimmed()

        guard !currentSubject.isEmpty, !currentGroup.isEmpty else {
            return nil
        }

        // Find all lessons in the same subject/group
        let candidates = lessons.filter { lesson in
            lesson.subject.trimmed().caseInsensitiveCompare(currentSubject) == .orderedSame &&
            lesson.group.trimmed().caseInsensitiveCompare(currentGroup) == .orderedSame
        }
        .sorted { $0.orderInGroup < $1.orderInGroup }

        // Find the current lesson's index
        guard let currentIndex = candidates.firstIndex(where: { $0.id == currentLesson.id }),
              currentIndex > 0 else {
            return nil // No preceding lesson
        }

        return candidates[currentIndex - 1]
    }

    // MARK: - Work Completion Checks

    /// Check if work is complete (either statusRaw == "complete" OR all relevant participants have completedAt).
    ///
    /// - Parameters:
    ///   - work: The WorkModel to check
    ///   - requiredStudentIDs: The student IDs that need to have completed the work
    /// - Returns: True if work is complete for all required students
    static func isWorkComplete(work: WorkModel, requiredStudentIDs: [UUID]) -> Bool {
        // Check if work status is complete
        if work.statusRaw == "complete" {
            return true
        }

        // Check if per-student completion: all relevant WorkParticipantEntity entries have completedAt != nil
        if let participants = work.participants, !participants.isEmpty {
            let requiredStudentIDStrings = Set(requiredStudentIDs.map { $0.uuidString })

            // Only check participants that are in the required student list (relevant participants)
            let relevantParticipants = participants.filter { participant in
                requiredStudentIDStrings.contains(participant.studentID)
            }

            // All relevant WorkParticipantEntity entries must have completedAt != nil
            // If there are no relevant participants, we can't check per-student completion, so fall back to status
            if relevantParticipants.isEmpty {
                return false // No relevant participants means not complete (status already checked)
            }

            return relevantParticipants.allSatisfy { $0.completedAt != nil }
        }

        // No participants means we check by status only (already checked above)
        return false
    }

    /// Check if work has incomplete status for any required student.
    ///
    /// - Parameters:
    ///   - work: The WorkModel to check
    ///   - requiredStudentIDs: The student IDs to check
    /// - Returns: True if any required student has incomplete work
    static func workHasIncompleteForRequiredStudents(work: WorkModel, requiredStudentIDs: [UUID]) -> Bool {
        // This is the inverse of isWorkComplete - if work is not complete, it has incomplete status
        return !isWorkComplete(work: work, requiredStudentIDs: requiredStudentIDs)
    }
}
