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
            guard let row = context.existing(CDLessonPresentation.self, state.objectID),
                  !row.isDeleted,
                  row.presentationID == presentationID else {
                continue
            }
            row.presentedAt = state.presentedAt
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
            guard let row = context.existing(CDLessonPresentation.self, objectID),
                  !row.isDeleted,
                  row.presentationID == presentationID else {
                continue
            }
            context.delete(row)
        }
    }
}
