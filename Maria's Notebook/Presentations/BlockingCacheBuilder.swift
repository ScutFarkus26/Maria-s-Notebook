import Foundation
import SwiftData

// MARK: - Blocking Cache Builder

/// Builder for constructing blocking work caches.
/// Pre-computes blocking relationships between StudentLessons and WorkModels for efficient lookup.
/// Uses LessonAssignment (unified model).
enum BlockingCacheBuilder {

    // MARK: - Types

    /// A cache mapping StudentLesson IDs to their blocking work by student.
    typealias BlockingCache = [UUID: [UUID: WorkModel]]

    // MARK: - Build Cache

    /// Build the blocking cache for all StudentLessons.
    /// Uses LessonAssignment (unified model).
    ///
    /// - Parameters:
    ///   - studentLessons: All StudentLessons
    ///   - lessons: All Lessons
    ///   - workModels: All WorkModels (preferably filtered to non-complete)
    ///   - lessonAssignments: All LessonAssignments (unified model)
    ///   - lessonAssignmentsByLegacyID: Map of LessonAssignments by migratedFromStudentLessonID
    ///   - openWorkByPresentationID: Map of open WorkModels by presentationID
    /// - Returns: A BlockingCache mapping StudentLesson IDs to blocking work
    static func buildCache(
        studentLessons: [StudentLesson],
        lessons: [Lesson],
        workModels: [WorkModel],
        lessonAssignments: [LessonAssignment] = [],
        lessonAssignmentsByLegacyID: [String: LessonAssignment] = [:],
        openWorkByPresentationID: [String: [WorkModel]]
    ) -> BlockingCache {
        var cache: BlockingCache = [:]

        // Build cache for all unscheduled student lessons using prerequisite blocking logic
        let unscheduled = studentLessons.filter { $0.scheduledFor == nil && !$0.isGiven }

        for sl in unscheduled {
            if let blocking = buildBlockingForUnscheduled(
                sl: sl,
                lessons: lessons,
                workModels: workModels,
                lessonAssignments: lessonAssignments
            ), !blocking.isEmpty {
                cache[sl.id] = blocking
            }
        }

        // Also build cache for presented lessons (for Inbox)
        let presented = studentLessons.filter { $0.isGiven }

        for sl in presented {
            if let blocking = buildBlockingForPresented(
                sl: sl,
                lessonAssignmentsByLegacyID: lessonAssignmentsByLegacyID,
                openWorkByPresentationID: openWorkByPresentationID
            ), !blocking.isEmpty {
                cache[sl.id] = blocking
            }
        }

        return cache
    }

    // MARK: - Private Helpers

    /// Build blocking dictionary for an unscheduled StudentLesson.
    /// Uses LessonAssignment (unified model).
    private static func buildBlockingForUnscheduled(
        sl: StudentLesson,
        lessons: [Lesson],
        workModels: [WorkModel],
        lessonAssignments: [LessonAssignment] = []
    ) -> [UUID: WorkModel]? {
        // Find the current lesson
        guard let currentLessonID = UUID(uuidString: sl.lessonID),
              let currentLesson = lessons.first(where: { $0.id == currentLessonID }) else {
            return nil
        }

        // Find the preceding lesson in the sequence
        guard let precedingLesson = BlockingAlgorithmEngine.findPrecedingLesson(
            currentLesson: currentLesson,
            lessons: lessons
        ) else {
            return nil // No preceding lesson means no prerequisites
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
            return nil // No presentation for preceding lesson means no prerequisites
        }

        // Find incomplete prerequisite work linked to the preceding presentation
        let prerequisiteWork = workModels.filter { work in
            work.presentationID == presentationID &&
            !BlockingAlgorithmEngine.isWorkComplete(work: work, requiredStudentIDs: sl.resolvedStudentIDs)
        }

        // Build blocking dictionary: map student IDs to their blocking work
        var blocking: [UUID: WorkModel] = [:]

        for work in prerequisiteWork {
            // For work with participants, map to specific students
            if let participants = work.participants, !participants.isEmpty {
                for participant in participants {
                    guard let studentID = UUID(uuidString: participant.studentID),
                          sl.resolvedStudentIDs.contains(studentID),
                          participant.completedAt == nil else {
                        continue
                    }
                    // Only add if not already added (first incomplete work per student)
                    if blocking[studentID] == nil {
                        blocking[studentID] = work
                    }
                }
            } else {
                // No participants: work blocks all students in the group
                for studentID in sl.resolvedStudentIDs {
                    if blocking[studentID] == nil {
                        blocking[studentID] = work
                    }
                }
            }
        }

        return blocking.isEmpty ? nil : blocking
    }

    /// Build blocking dictionary for a presented StudentLesson.
    /// Uses LessonAssignment (unified model).
    private static func buildBlockingForPresented(
        sl: StudentLesson,
        lessonAssignmentsByLegacyID: [String: LessonAssignment] = [:],
        openWorkByPresentationID: [String: [WorkModel]]
    ) -> [UUID: WorkModel]? {
        let legacyID = sl.id.uuidString

        // Find in LessonAssignment (unified model)
        guard let lessonAssignment = lessonAssignmentsByLegacyID[legacyID] else {
            return nil
        }

        let presentationID = lessonAssignment.id.uuidString

        guard !presentationID.isEmpty else {
            return nil
        }

        // Get open work for this presentation from openWorkByPresentationID
        guard let openWork = openWorkByPresentationID[presentationID], !openWork.isEmpty else {
            return nil
        }

        // Build blocking dictionary for all students with unresolved work
        var blocking: [UUID: WorkModel] = [:]

        for studentIDString in sl.studentIDs {
            guard let studentID = UUID(uuidString: studentIDString) else { continue }

            if let work = openWork.first(where: { w in
                w.presentationID == presentationID &&
                w.studentID == studentIDString &&
                w.statusRaw != "complete"
            }) {
                blocking[studentID] = work
            }
        }

        return blocking.isEmpty ? nil : blocking
    }
}
