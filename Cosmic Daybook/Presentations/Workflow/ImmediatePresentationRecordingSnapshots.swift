import CoreData
import Foundation

extension ImmediatePresentationRecordingService {
    struct RecordPreparation {
        let assignmentID: UUID
        let presentedDay: Date
        let assignmentState: AssignmentStateSnapshot
        let existingHistoryIdentities: Set<ObjectIdentifier>
        let priorHistoryStates: [HistoryStateBeforeSave]
        let releasePreimage: YearPlanReleasePreimage
    }

    struct RecordChanges {
        let createdHistoryRows: [CDLessonPresentation]
        let releasedPlans: YearPlanReleasePreimage
    }

    struct AssignmentStateSnapshot {
        let stateRaw: String
        let presentedAt: Date?
        let scheduledFor: Date?
        let scheduledForDay: Date?
        let needsAnotherPresentation: Bool
        let modifiedAt: Date?
        let lessonTitleSnapshot: String?
        let lessonSectionSnapshot: String?
        let studentIDs: [String]

        init(assignment: CDLessonAssignment) {
            stateRaw = assignment.stateRaw
            presentedAt = assignment.presentedAt
            scheduledFor = assignment.scheduledFor
            scheduledForDay = assignment.scheduledForDay
            needsAnotherPresentation = assignment.needsAnotherPresentation
            modifiedAt = assignment.modifiedAt
            lessonTitleSnapshot = assignment.lessonTitleSnapshot
            lessonSectionSnapshot = assignment.lessonSectionSnapshot
            studentIDs = assignment.studentIDs
        }

        func restore(_ assignment: CDLessonAssignment) {
            assignment.stateRaw = stateRaw
            assignment.presentedAt = presentedAt
            assignment.scheduledFor = scheduledFor
            assignment.scheduledForDay = scheduledForDay
            assignment.needsAnotherPresentation = needsAnotherPresentation
            assignment.modifiedAt = modifiedAt
            assignment.lessonTitleSnapshot = lessonTitleSnapshot
            assignment.lessonSectionSnapshot = lessonSectionSnapshot
            assignment.studentIDs = studentIDs
        }
    }

    struct HistoryStateSnapshot {
        let objectID: NSManagedObjectID
        let presentedAt: Date?
        let lastObservedAt: Date?
        let followUpActionRaw: String?
        let followUpReviewAt: Date?
        let followUpResolvedAt: Date?
        let followUpResolutionRaw: String?
        let followUpUpdatedAt: Date?
        let followUpEvidenceRaw: String?
        let followUpNote: String?
        let followUpSupportRaw: String?
    }

    struct HistoryStateBeforeSave {
        let row: CDLessonPresentation
        let presentedAt: Date?
        let lastObservedAt: Date?
        let followUpActionRaw: String?
        let followUpReviewAt: Date?
        let followUpResolvedAt: Date?
        let followUpResolutionRaw: String?
        let followUpUpdatedAt: Date?
        let followUpEvidenceRaw: String?
        let followUpNote: String?
        let followUpSupportRaw: String?

        init(row: CDLessonPresentation, lastObservedAt: Date?) {
            self.row = row
            self.presentedAt = row.presentedAt
            self.lastObservedAt = lastObservedAt
            followUpActionRaw = row.followUpActionRaw
            followUpReviewAt = row.followUpReviewAt
            followUpResolvedAt = row.followUpResolvedAt
            followUpResolutionRaw = row.followUpResolutionRaw
            followUpUpdatedAt = row.followUpUpdatedAt
            followUpEvidenceRaw = row.followUpEvidenceRaw
            followUpNote = row.followUpNote
            followUpSupportRaw = row.followUpSupportRaw
        }
    }
}
