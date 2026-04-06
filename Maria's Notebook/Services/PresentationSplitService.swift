import Foundation
import CoreData

/// Splits a mixed-readiness lesson assignment into two: one for ready students, one for blocked.
@MainActor
enum PresentationSplitService {

    /// Split ready students out of a blocked assignment into a new assignment.
    ///
    /// - Parameters:
    ///   - assignment: The original (blocked) assignment.
    ///   - readyStudentIDs: Students who are ready to proceed.
    ///   - asDraft: If true, the new assignment is a draft (inbox). If false, it's scheduled.
    ///   - scheduledFor: The date to schedule (used when `asDraft` is false).
    ///   - context: The managed object context.
    /// - Returns: The new assignment for ready students, or nil if split isn't possible.
    @discardableResult
    static func splitReadyStudents(
        from assignment: CDLessonAssignment,
        readyStudentIDs: [UUID],
        asDraft: Bool,
        scheduledFor: Date? = nil,
        context: NSManagedObjectContext
    ) -> CDLessonAssignment? {
        guard !readyStudentIDs.isEmpty else { return nil }

        let allStudentIDs = assignment.studentUUIDs
        let readySet = Set(readyStudentIDs)
        let remainingIDs = allStudentIDs.filter { !readySet.contains($0) }

        // Don't split if all or none are ready
        guard !remainingIDs.isEmpty, !readyStudentIDs.isEmpty else { return nil }

        // Create new assignment for ready students
        let newAssignment: CDLessonAssignment
        if asDraft {
            newAssignment = PresentationFactory.makeDraft(
                lessonID: UUID(uuidString: assignment.lessonID) ?? UUID(),
                studentIDs: readyStudentIDs,
                context: context
            )
        } else {
            let date = scheduledFor ?? Date()
            newAssignment = PresentationFactory.makeScheduled(
                lessonID: UUID(uuidString: assignment.lessonID) ?? UUID(),
                studentIDs: readyStudentIDs,
                scheduledFor: date,
                context: context
            )
        }

        // Copy relevant metadata
        newAssignment.lessonTitleSnapshot = assignment.lessonTitleSnapshot
        newAssignment.lessonSubheadingSnapshot = assignment.lessonSubheadingSnapshot
        newAssignment.trackID = assignment.trackID
        newAssignment.trackStepID = assignment.trackStepID

        // Update original assignment to only contain blocked students
        assignment.studentIDs = remainingIDs.map(\.uuidString)
        assignment.modifiedAt = Date()

        return newAssignment
    }
}
