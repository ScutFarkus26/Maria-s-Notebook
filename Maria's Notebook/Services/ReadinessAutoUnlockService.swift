import Foundation
import CoreData
import OSLog

/// Checks whether completing work or confirming proficiency unlocks the next lesson for a student.
/// Called after work completion and after teacher marks a student as proficient.
@MainActor
enum ReadinessAutoUnlockService {
    private static let logger = Logger.app(category: "ReadinessAutoUnlock")

    /// Check if completing work for a student on a given lesson unlocks the next lesson.
    /// If all students on a blocked assignment become ready, the assignment moves from On Deck to inbox.
    ///
    /// - Parameters:
    ///   - lessonID: The lesson whose work was just completed.
    ///   - studentID: The student who completed the work.
    ///   - context: The managed object context.
    static func checkAndUnlock(
        afterWorkOn lessonID: UUID,
        studentID: UUID,
        context: NSManagedObjectContext
    ) {
        // Find the next lesson in the sequence
        let allLessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        guard let currentLesson = allLessons.first(where: { $0.id == lessonID }) else { return }
        guard let nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: allLessons) else { return }
        guard let nextLessonID = nextLesson.id else { return }

        // Find any draft/scheduled assignments for the next lesson that include this student
        let allAssignments = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        let candidateAssignments = allAssignments.filter { la in
            la.lessonIDUUID == nextLessonID &&
            !la.isPresented &&
            la.resolvedStudentIDs.contains(studentID)
        }

        guard !candidateAssignments.isEmpty else { return }

        // Re-check blocking for these assignments
        let workModels = context.safeFetch(CDFetchRequest(CDWorkModel.self))
        let results = BlockingAlgorithmEngine.checkBlocking(
            forBatch: candidateAssignments,
            lessons: allLessons,
            allLessonAssignments: allAssignments,
            workModels: workModels
        )

        for la in candidateAssignments {
            guard let laID = la.id, let result = results[laID] else { continue }

            if !result.isBlocked && la.manuallyUnblocked == false {
                // All students ready — assignment naturally moves from On Deck to inbox
                // (The PresentationsViewModel will pick this up on next refresh)
                logger.info("Auto-unlocked assignment \(laID) — all students ready")
            }
        }
    }

    /// Check if confirming a student's proficiency on a lesson unlocks the next lesson.
    static func checkAndUnlock(
        afterConfirmationOn lessonID: UUID,
        studentID: UUID,
        context: NSManagedObjectContext
    ) {
        // Same logic — confirmation is just another gate
        checkAndUnlock(afterWorkOn: lessonID, studentID: studentID, context: context)
    }
}
