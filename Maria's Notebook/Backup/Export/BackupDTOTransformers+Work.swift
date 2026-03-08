import Foundation
import SwiftData

// MARK: - Work Transformers (WorkModel, WorkCheckIn, WorkStep, WorkParticipant, PracticeSession)

extension BackupDTOTransformers {

    // MARK: - WorkModel

    static func toDTO(_ work: WorkModel) -> WorkModelDTO {
        WorkModelDTO(
            id: work.id,
            title: work.title,
            workTypeRaw: work.workTypeRaw,
            studentLessonID: work.studentLessonID,
            createdAt: work.createdAt,
            completedAt: work.completedAt,
            kindRaw: work.kindRaw,
            statusRaw: work.statusRaw,
            assignedAt: work.assignedAt,
            lastTouchedAt: work.lastTouchedAt,
            dueAt: work.dueAt,
            completionOutcomeRaw: work.completionOutcomeRaw,
            legacyContractID: work.legacyContractID,
            studentID: work.studentID,
            lessonID: work.lessonID,
            presentationID: work.presentationID,
            trackID: work.trackID,
            trackStepID: work.trackStepID,
            scheduledNote: work.scheduledNote,
            scheduledReasonRaw: work.scheduledReasonRaw,
            sourceContextTypeRaw: work.sourceContextTypeRaw,
            sourceContextID: work.sourceContextID,
            sampleWorkID: work.sampleWorkID,
            legacyStudentLessonID: work.legacyStudentLessonID,
            checkInStyleRaw: work.checkInStyleRaw
        )
    }

    // MARK: - WorkCheckIn

    static func toDTO(_ checkIn: WorkCheckIn) -> WorkCheckInDTO {
        WorkCheckInDTO(
            id: checkIn.id,
            workID: checkIn.workID,
            date: checkIn.date,
            statusRaw: checkIn.statusRaw,
            purpose: checkIn.purpose
        )
    }

    // MARK: - WorkStep

    static func toDTO(_ step: WorkStep) -> WorkStepDTO {
        WorkStepDTO(
            id: step.id,
            workID: step.work?.id,
            orderIndex: step.orderIndex,
            title: step.title,
            instructions: step.instructions,
            completedAt: step.completedAt,
            notes: step.notes,
            completionOutcomeRaw: step.completionOutcomeRaw,
            createdAt: step.createdAt
        )
    }

    // MARK: - WorkParticipantEntity

    static func toDTO(_ participant: WorkParticipantEntity) -> WorkParticipantEntityDTO {
        WorkParticipantEntityDTO(
            id: participant.id,
            studentID: participant.studentID,
            completedAt: participant.completedAt,
            workID: participant.work?.id
        )
    }

    // MARK: - PracticeSession

    static func toDTO(_ session: PracticeSession) -> PracticeSessionDTO {
        PracticeSessionDTO(
            id: session.id,
            createdAt: session.createdAt,
            date: session.date,
            duration: session.duration,
            studentIDs: session.studentIDs,
            workItemIDs: session.workItemIDs,
            sharedNotes: session.sharedNotes,
            location: session.location,
            practiceQuality: session.practiceQuality,
            independenceLevel: session.independenceLevel,
            askedForHelp: session.askedForHelp,
            helpedPeer: session.helpedPeer,
            struggledWithConcept: session.struggledWithConcept,
            madeBreakthrough: session.madeBreakthrough,
            needsReteaching: session.needsReteaching,
            readyForCheckIn: session.readyForCheckIn,
            readyForAssessment: session.readyForAssessment,
            checkInScheduledFor: session.checkInScheduledFor,
            followUpActions: session.followUpActions,
            materialsUsed: session.materialsUsed,
            workStepID: session.workStepID
        )
    }

    // MARK: - Batch Transformations (Work)

    static func toDTOs(_ works: [WorkModel]) -> [WorkModelDTO] {
        works.map { toDTO($0) }
    }

    static func toDTOs(_ checkIns: [WorkCheckIn]) -> [WorkCheckInDTO] {
        checkIns.map { toDTO($0) }
    }

    static func toDTOs(_ steps: [WorkStep]) -> [WorkStepDTO] {
        steps.map { toDTO($0) }
    }

    static func toDTOs(_ participants: [WorkParticipantEntity]) -> [WorkParticipantEntityDTO] {
        participants.map { toDTO($0) }
    }

    static func toDTOs(_ sessions: [PracticeSession]) -> [PracticeSessionDTO] {
        sessions.map { toDTO($0) }
    }
}
