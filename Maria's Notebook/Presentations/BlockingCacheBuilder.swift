import Foundation
import SwiftData

// MARK: - Blocking Cache Builder

/// Builder for constructing blocking work caches.
/// Pre-computes blocking relationships between LessonAssignments and WorkModels for efficient lookup.
enum BlockingCacheBuilder {

    // MARK: - Types

    /// A cache mapping LessonAssignment IDs to their blocking work by student.
    typealias BlockingCache = [UUID: [UUID: WorkModel]]

    // MARK: - Build Cache

    /// Build the blocking cache for all LessonAssignments.
    ///
    /// - Parameters:
    ///   - lessonAssignments: All LessonAssignments
    ///   - lessons: All Lessons
    ///   - workModels: All WorkModels (preferably filtered to non-complete)
    ///   - openWorkByPresentationID: Map of open WorkModels by presentationID
    /// - Returns: A BlockingCache mapping LessonAssignment IDs to blocking work
    static func buildCache(
        lessonAssignments: [LessonAssignment],
        lessons: [Lesson],
        workModels: [WorkModel],
        openWorkByPresentationID: [String: [WorkModel]]
    ) -> BlockingCache {
        var cache: BlockingCache = [:]

        // Build cache for all unscheduled lesson assignments using prerequisite blocking logic
        let unscheduled = lessonAssignments.filter { $0.scheduledFor == nil && !$0.isGiven }

        for la in unscheduled {
            if let blocking = buildBlockingForUnscheduled(
                la: la,
                lessons: lessons,
                workModels: workModels,
                lessonAssignments: lessonAssignments
            ), !blocking.isEmpty {
                cache[la.id] = blocking
            }
        }

        // Also build cache for presented assignments (for Inbox)
        let presented = lessonAssignments.filter { $0.isGiven }

        for la in presented {
            if let blocking = buildBlockingForPresented(
                la: la,
                openWorkByPresentationID: openWorkByPresentationID
            ), !blocking.isEmpty {
                cache[la.id] = blocking
            }
        }

        return cache
    }

    // MARK: - Private Helpers

    /// Build blocking dictionary for an unscheduled LessonAssignment.
    private static func buildBlockingForUnscheduled(
        la: LessonAssignment,
        lessons: [Lesson],
        workModels: [WorkModel],
        lessonAssignments: [LessonAssignment]
    ) -> [UUID: WorkModel]? {
        // Find the current lesson
        guard let currentLessonID = UUID(uuidString: la.lessonID),
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
        let studentIDs = Set(la.resolvedStudentIDs.map { $0.uuidString })

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
            !BlockingAlgorithmEngine.isWorkComplete(work: work, requiredStudentIDs: la.resolvedStudentIDs)
        }

        // Build blocking dictionary: map student IDs to their blocking work
        var blocking: [UUID: WorkModel] = [:]

        for work in prerequisiteWork {
            if let participants = work.participants, !participants.isEmpty {
                for participant in participants {
                    guard let studentID = UUID(uuidString: participant.studentID),
                          la.resolvedStudentIDs.contains(studentID),
                          participant.completedAt == nil else {
                        continue
                    }
                    if blocking[studentID] == nil {
                        blocking[studentID] = work
                    }
                }
            } else {
                for studentID in la.resolvedStudentIDs where blocking[studentID] == nil {
                    blocking[studentID] = work
                }
            }
        }

        return blocking.isEmpty ? nil : blocking
    }

    /// Build blocking dictionary for a presented LessonAssignment.
    private static func buildBlockingForPresented(
        la: LessonAssignment,
        openWorkByPresentationID: [String: [WorkModel]]
    ) -> [UUID: WorkModel]? {
        let presentationID = la.id.uuidString

        guard !presentationID.isEmpty else {
            return nil
        }

        // Get open work for this presentation
        guard let openWork = openWorkByPresentationID[presentationID], !openWork.isEmpty else {
            return nil
        }

        // Build blocking dictionary for all students with unresolved work
        var blocking: [UUID: WorkModel] = [:]

        for studentIDString in la.studentIDs {
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
