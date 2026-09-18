import CoreData
import Foundation

extension ImmediatePresentationRecordingService {
    static func historyRows(
        for assignmentID: UUID,
        in context: NSManagedObjectContext
    ) throws -> [CDLessonPresentation] {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@",
            assignmentID.uuidString
        )
        return try context.fetch(request)
    }

    static func restoreExistingHistory(
        _ token: UndoToken,
        in context: NSManagedObjectContext
    ) {
        let presentationID = token.assignmentID.uuidString
        for state in token.existingHistoryStates {
            guard let row = try? context.existingObject(with: state.objectID)
                as? CDLessonPresentation,
                  !row.isDeleted,
                  row.presentationID == presentationID else {
                continue
            }
            row.lastObservedAt = state.lastObservedAt
            row.followUpActionRaw = state.followUpActionRaw
            row.followUpReviewAt = state.followUpReviewAt
            row.followUpResolvedAt = state.followUpResolvedAt
            row.followUpResolutionRaw = state.followUpResolutionRaw
            row.followUpUpdatedAt = state.followUpUpdatedAt
            row.followUpEvidenceRaw = state.followUpEvidenceRaw
            row.followUpNote = state.followUpNote
            row.followUpSupportRaw = state.followUpSupportRaw
        }
    }

    static func deleteHistoryCreatedByRecord(
        _ token: UndoToken,
        in context: NSManagedObjectContext
    ) {
        let presentationID = token.assignmentID.uuidString
        for objectID in token.createdHistoryObjectIDs {
            guard let row = try? context.existingObject(with: objectID)
                as? CDLessonPresentation,
                  !row.isDeleted,
                  row.presentationID == presentationID else {
                continue
            }
            context.delete(row)
        }
    }

    static func enrollmentRows(
        for studentIDs: Set<String>,
        in context: NSManagedObjectContext
    ) -> [CDStudentTrackEnrollmentEntity] {
        guard !studentIDs.isEmpty else { return [] }
        let request = CDFetchRequest(CDStudentTrackEnrollmentEntity.self)
        return context.safeFetch(request).filter { studentIDs.contains($0.studentID) }
    }

    static func restoreExistingEnrollments(
        _ token: UndoToken,
        in context: NSManagedObjectContext
    ) {
        for state in token.existingEnrollmentStates {
            guard let enrollment = try? context.existingObject(with: state.objectID)
                as? CDStudentTrackEnrollmentEntity,
                  !enrollment.isDeleted else {
                continue
            }
            state.restore(enrollment, in: context)
        }
    }

    static func deleteEnrollmentsCreatedByRecord(
        _ token: UndoToken,
        in context: NSManagedObjectContext
    ) {
        for objectID in token.createdEnrollmentObjectIDs {
            guard let enrollment = try? context.existingObject(with: objectID)
                as? CDStudentTrackEnrollmentEntity,
                  !enrollment.isDeleted else {
                continue
            }
            context.delete(enrollment)
        }
    }
}
