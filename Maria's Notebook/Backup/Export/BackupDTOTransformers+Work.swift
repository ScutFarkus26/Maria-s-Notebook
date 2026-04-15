import Foundation
import CoreData

// MARK: - Work Transformers (CDWorkModel, CDWorkCheckIn, CDWorkStep, WorkParticipant, CDPracticeSession)

extension BackupDTOTransformers {

    // MARK: - CDWorkModel

    static func toDTO(_ work: CDWorkModel) -> WorkModelDTO {
        WorkModelDTO(
            id: work.id ?? UUID(),
            title: work.title,
            workTypeRaw: work.workTypeRaw,
            studentLessonID: work.studentLessonID,
            createdAt: work.createdAt ?? Date(),
            completedAt: work.completedAt,
            kindRaw: work.kindRaw,
            statusRaw: work.statusRaw,
            assignedAt: work.assignedAt ?? Date(),
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
            checkInStyleRaw: work.checkInStyleRaw,
            restingUntil: work.restingUntil
        )
    }

    // MARK: - CDWorkCheckIn

    static func toDTO(_ checkIn: CDWorkCheckIn) -> WorkCheckInDTO {
        WorkCheckInDTO(
            id: checkIn.id ?? UUID(),
            workID: checkIn.workID,
            date: checkIn.date ?? Date(),
            statusRaw: checkIn.statusRaw,
            purpose: checkIn.purpose
        )
    }

    // MARK: - CDWorkStep

    static func toDTO(_ step: CDWorkStep) -> WorkStepDTO {
        WorkStepDTO(
            id: step.id ?? UUID(),
            workID: step.work?.id,
            orderIndex: Int(step.orderIndex),
            title: step.title,
            instructions: step.instructions,
            completedAt: step.completedAt,
            notes: step.notes,
            completionOutcomeRaw: step.completionOutcomeRaw,
            createdAt: step.createdAt ?? Date()
        )
    }

    // MARK: - CDWorkParticipantEntity

    static func toDTO(_ participant: CDWorkParticipantEntity) -> WorkParticipantEntityDTO {
        WorkParticipantEntityDTO(
            id: participant.id ?? UUID(),
            studentID: participant.studentID,
            completedAt: participant.completedAt,
            workID: participant.work?.id
        )
    }

    // MARK: - CDPracticeSession

    static func toDTO(_ session: CDPracticeSession) -> PracticeSessionDTO {
        PracticeSessionDTO(
            id: session.id ?? UUID(),
            createdAt: session.createdAt ?? Date(),
            date: session.date ?? Date(),
            duration: session.duration > 0 ? session.duration : nil,
            studentIDs: (session.studentIDs as? [String]) ?? [],
            workItemIDs: (session.workItemIDs as? [String]) ?? [],
            sharedNotes: session.sharedNotes,
            location: session.location,
            practiceQuality: session.practiceQuality > 0 ? Int(session.practiceQuality) : nil,
            independenceLevel: session.independenceLevel > 0 ? Int(session.independenceLevel) : nil,
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

    static func toDTOs(_ works: [CDWorkModel]) -> [WorkModelDTO] {
        works.map { toDTO($0) }
    }

    static func toDTOs(_ checkIns: [CDWorkCheckIn]) -> [WorkCheckInDTO] {
        checkIns.map { toDTO($0) }
    }

    static func toDTOs(_ steps: [CDWorkStep]) -> [WorkStepDTO] {
        steps.map { toDTO($0) }
    }

    static func toDTOs(_ participants: [CDWorkParticipantEntity]) -> [WorkParticipantEntityDTO] {
        participants.map { toDTO($0) }
    }

    static func toDTOs(_ sessions: [CDPracticeSession]) -> [PracticeSessionDTO] {
        sessions.map { toDTO($0) }
    }
}
