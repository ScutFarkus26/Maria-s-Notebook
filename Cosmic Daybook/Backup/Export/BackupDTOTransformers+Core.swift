import Foundation
import CoreData

// MARK: - Core Transformers (CDSampleWork, CDSampleWorkStep, CDLessonAttachment,
//         CDLessonPresentation, CDLessonRecallCheck)
// CDStudent, CDLesson, and CDNote exports go through BackupServiceHelpers.toDTOs,
// which carries the full field set — do not re-add transformers for them here.

extension BackupDTOTransformers {

    // MARK: - CDSampleWork

    static func toDTO(_ sw: CDSampleWork) -> SampleWorkDTO {
        SampleWorkDTO(
            id: sw.id ?? UUID(),
            lessonID: (sw.lesson as? CDLesson)?.id,
            title: sw.title,
            workKindRaw: sw.workKindRaw,
            orderIndex: Int(sw.orderIndex),
            notes: sw.notes,
            createdAt: sw.createdAt ?? Date()
        )
    }

    // MARK: - CDLessonPresentation

    static func toDTO(_ lp: CDLessonPresentation) -> LessonPresentationDTO {
        LessonPresentationDTO(
            id: lp.id ?? UUID(),
            createdAt: lp.createdAt ?? Date(),
            studentID: lp.studentID,
            lessonID: lp.lessonID,
            presentationID: lp.presentationID,
            trackID: lp.trackID,
            trackStepID: lp.trackStepID,
            stateRaw: lp.stateRaw,
            presentedAt: lp.presentedAt ?? Date(),
            lastObservedAt: lp.lastObservedAt,
            masteredAt: lp.masteredAt,
            notes: lp.notes,
            followUpActionRaw: lp.followUpActionRaw,
            followUpReviewAt: lp.followUpReviewAt,
            followUpResolvedAt: lp.followUpResolvedAt,
            followUpResolutionRaw: lp.followUpResolutionRaw,
            followUpUpdatedAt: lp.followUpUpdatedAt,
            followUpEvidenceRaw: lp.followUpEvidenceRaw,
            followUpNote: lp.followUpNote,
            followUpSupportRaw: lp.followUpSupportRaw
        )
    }

    // MARK: - Batch Transformations (Core)

    static func toDTOs(_ sampleWorks: [CDSampleWork]) -> [SampleWorkDTO] {
        sampleWorks.map { toDTO($0) }
    }

    static func toDTOs(_ presentations: [CDLessonPresentation]) -> [LessonPresentationDTO] {
        presentations.map { toDTO($0) }
    }

}
