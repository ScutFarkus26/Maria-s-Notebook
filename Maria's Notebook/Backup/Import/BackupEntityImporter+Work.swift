import Foundation
import SwiftData
import OSLog

// MARK: - Work

extension BackupEntityImporter {

    // MARK: - WorkModel

    /// Imports WorkModel records from DTOs. Must run BEFORE child entities (check-ins, steps, participants).
    static func importWorkModels(
        _ dtos: [WorkModelDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<WorkModel>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let work = WorkModel(
                    id: dto.id,
                    title: dto.title,
                    kind: dto.kindRaw.flatMap { WorkKind(rawValue: $0) } ?? .research,
                    studentLessonID: dto.studentLessonID,
                    createdAt: dto.createdAt,
                    completedAt: dto.completedAt,
                    status: WorkStatus(rawValue: dto.statusRaw) ?? .active,
                    assignedAt: dto.assignedAt,
                    lastTouchedAt: dto.lastTouchedAt,
                    dueAt: dto.dueAt,
                    completionOutcome: dto.completionOutcomeRaw.flatMap { CompletionOutcome(rawValue: $0) },
                    legacyContractID: dto.legacyContractID,
                    studentID: dto.studentID,
                    lessonID: dto.lessonID,
                    presentationID: dto.presentationID,
                    trackID: dto.trackID,
                    trackStepID: dto.trackStepID,
                    scheduledNote: dto.scheduledNote,
                    scheduledReason: dto.scheduledReasonRaw.flatMap { ScheduledReason(rawValue: $0) },
                    sourceContextType: dto.sourceContextTypeRaw.flatMap { WorkSourceContextType(rawValue: $0) },
                    sourceContextID: dto.sourceContextID,
                    legacyStudentLessonID: dto.legacyStudentLessonID
                )
                work.sampleWorkID = dto.sampleWorkID
                work.checkInStyleRaw = dto.checkInStyleRaw
                return work
            })
    }

    // MARK: - Work Completion Records

    /// Imports work completion records from DTOs.
    static func importWorkCompletionRecords(
        _ dtos: [WorkCompletionRecordDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<WorkCompletionRecord>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            WorkCompletionRecord(id: dto.id, workID: dto.workID, studentID: dto.studentID, completedAt: dto.completedAt)
        })
    }

    // MARK: - Work Check-Ins

    static func importWorkCheckIns(
        _ dtos: [WorkCheckInDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<WorkCheckIn>,
        workCheck: EntityExistsCheck<WorkModel>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let workUUID = UUID(uuidString: dto.workID) else { continue }
            let checkIn = WorkCheckIn(
                id: dto.id,
                workID: workUUID,
                date: dto.date,
                status: WorkCheckInStatus(rawValue: dto.statusRaw) ?? .scheduled,
                purpose: dto.purpose
            )
            // Link to work if exists
            do {
                if let work = try workCheck(workUUID) {
                    checkIn.work = work
                }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check work for check-in: \(desc, privacy: .public)")
            }
            modelContext.insert(checkIn)
        }
    }

    // MARK: - Work Steps

    static func importWorkSteps(
        _ dtos: [WorkStepDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<WorkStep>,
        workCheck: EntityExistsCheck<WorkModel>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let step = WorkStep(
                id: dto.id,
                orderIndex: dto.orderIndex,
                title: dto.title,
                instructions: dto.instructions,
                completedAt: dto.completedAt,
                notes: dto.notes,
                completionOutcomeRaw: dto.completionOutcomeRaw,
                createdAt: dto.createdAt
            )
            if let workID = dto.workID {
                do {
                    if let work = try workCheck(workID) {
                        step.work = work
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check work for step: \(desc, privacy: .public)")
                }
            }
            modelContext.insert(step)
        }
    }

    // MARK: - Work Participants

    static func importWorkParticipants(
        _ dtos: [WorkParticipantEntityDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<WorkParticipantEntity>,
        workCheck: EntityExistsCheck<WorkModel>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let studentUUID = UUID(uuidString: dto.studentID) else { continue }
            let participant = WorkParticipantEntity(id: dto.id, studentID: studentUUID, completedAt: dto.completedAt)
            if let workID = dto.workID {
                do {
                    if let work = try workCheck(workID) {
                        participant.work = work
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check work for participant: \(desc, privacy: .public)")
                }
            }
            modelContext.insert(participant)
        }
    }

    // MARK: - Practice Sessions

    static func importPracticeSessions(
        _ dtos: [PracticeSessionDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<PracticeSession>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let session = PracticeSession()
            session.id = dto.id
            session.createdAt = dto.createdAt
            session.date = dto.date
            session.duration = dto.duration
            session.studentIDs = dto.studentIDs
            session.workItemIDs = dto.workItemIDs
            session.sharedNotes = dto.sharedNotes
            session.location = dto.location
            session.practiceQuality = dto.practiceQuality
            session.independenceLevel = dto.independenceLevel
            session.askedForHelp = dto.askedForHelp
            session.helpedPeer = dto.helpedPeer
            session.struggledWithConcept = dto.struggledWithConcept
            session.madeBreakthrough = dto.madeBreakthrough
            session.needsReteaching = dto.needsReteaching
            session.readyForCheckIn = dto.readyForCheckIn
            session.readyForAssessment = dto.readyForAssessment
            session.checkInScheduledFor = dto.checkInScheduledFor
            session.followUpActions = dto.followUpActions
            session.materialsUsed = dto.materialsUsed
            session.workStepID = dto.workStepID
            return session
        })
    }
}
