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

    // MARK: - CDSampleWorkStep

    static func toDTO(_ step: CDSampleWorkStep) -> SampleWorkStepDTO {
        SampleWorkStepDTO(
            id: step.id ?? UUID(),
            sampleWorkID: step.sampleWork?.id,
            title: step.title,
            orderIndex: Int(step.orderIndex),
            instructions: step.instructions,
            createdAt: step.createdAt ?? Date()
        )
    }

    // MARK: - CDLessonAttachment

    static func toDTO(_ attachment: CDLessonAttachment) -> LessonAttachmentDTO {
        LessonAttachmentDTO(
            id: attachment.id ?? UUID(),
            fileName: attachment.fileName,
            fileRelativePath: attachment.fileRelativePath,
            attachedAt: attachment.attachedAt ?? Date(),
            fileType: attachment.fileType,
            fileSizeBytes: attachment.fileSizeBytes,
            scopeRaw: attachment.scopeRaw,
            notes: attachment.notes,
            lessonID: attachment.lesson?.id
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

    static func toDTOs(_ sampleWorkSteps: [CDSampleWorkStep]) -> [SampleWorkStepDTO] {
        sampleWorkSteps.map { toDTO($0) }
    }

    static func toDTOs(_ attachments: [CDLessonAttachment]) -> [LessonAttachmentDTO] {
        attachments.map { toDTO($0) }
    }

    static func toDTOs(_ presentations: [CDLessonPresentation]) -> [LessonPresentationDTO] {
        presentations.map { toDTO($0) }
    }

    // MARK: - CDLessonRecallCheck

    static func toDTO(_ rc: CDLessonRecallCheck) -> LessonRecallCheckDTO {
        LessonRecallCheckDTO(
            id: rc.id ?? UUID(),
            createdAt: rc.createdAt ?? Date(),
            modifiedAt: rc.modifiedAt,
            studentID: rc.studentID,
            lessonID: rc.lessonID,
            outcomeRaw: rc.outcomeRaw,
            sourceRaw: rc.sourceRaw,
            coveredByLessonID: rc.coveredByLessonID,
            presentationID: rc.presentationID,
            originalMasteredAt: rc.originalMasteredAt,
            checkedAt: rc.checkedAt,
            note: rc.note,
            photoRef: rc.photoRef,
            schoolYearKey: rc.schoolYearKey
        )
    }

    static func toDTOs(_ checks: [CDLessonRecallCheck]) -> [LessonRecallCheckDTO] {
        checks.map { toDTO($0) }
    }
}
