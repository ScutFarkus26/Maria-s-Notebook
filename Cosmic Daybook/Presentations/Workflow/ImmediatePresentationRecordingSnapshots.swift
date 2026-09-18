import CoreData
import Foundation

extension ImmediatePresentationRecordingService {
    struct RecordPreparation {
        let assignmentID: UUID
        let presentedDay: Date
        let assignmentState: AssignmentStateSnapshot
        let existingHistoryIdentities: Set<ObjectIdentifier>
        let priorHistoryStates: [HistoryStateBeforeSave]
        let existingEnrollmentIdentities: Set<ObjectIdentifier>
        let priorEnrollmentStates: [EnrollmentStateBeforeSave]
    }

    struct RecordChanges {
        let createdHistoryRows: [CDLessonPresentation]
        let createdEnrollmentRows: [CDStudentTrackEnrollmentEntity]
        let existingEnrollmentStates: [EnrollmentStateSnapshot]
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
        let trackID: String?
        let trackStepID: String?
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
            trackID = assignment.trackID
            trackStepID = assignment.trackStepID
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
            assignment.trackID = trackID
            assignment.trackStepID = trackStepID
            assignment.studentIDs = studentIDs
        }
    }

    struct HistoryStateSnapshot {
        let objectID: NSManagedObjectID
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

    struct EnrollmentStateBeforeSave {
        let row: CDStudentTrackEnrollmentEntity
        let trackID: String
        let isActive: Bool
        let startedAt: Date?
        let trackObjectID: NSManagedObjectID?
        let studentObjectID: NSManagedObjectID?

        init(_ row: CDStudentTrackEnrollmentEntity) {
            self.row = row
            trackID = row.trackID
            isActive = row.isActive
            startedAt = row.startedAt
            trackObjectID = row.track?.objectID
            studentObjectID = row.student?.objectID
        }
    }

    struct EnrollmentStateSnapshot {
        let objectID: NSManagedObjectID
        let isActive: Bool
        let startedAt: Date?
        let trackObjectID: NSManagedObjectID?
        let studentObjectID: NSManagedObjectID?

        init(_ state: EnrollmentStateBeforeSave) {
            objectID = state.row.objectID
            isActive = state.isActive
            startedAt = state.startedAt
            trackObjectID = state.trackObjectID
            studentObjectID = state.studentObjectID
        }

        func restore(
            _ enrollment: CDStudentTrackEnrollmentEntity,
            in context: NSManagedObjectContext
        ) {
            enrollment.isActive = isActive
            enrollment.startedAt = startedAt
            enrollment.track = trackObjectID
                .flatMap { try? context.existingObject(with: $0) }
                .flatMap { $0 as? CDTrackEntity }
            enrollment.student = studentObjectID
                .flatMap { try? context.existingObject(with: $0) }
                .flatMap { $0 as? CDStudent }
        }
    }
}
