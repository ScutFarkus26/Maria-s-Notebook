import Foundation
import SwiftData

// MARK: - Work

extension BackupEntityImporter {

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
                print("⚠️ [Backup:\(#function)] Failed to check work for check-in: \(error)")
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
                createdAt: dto.createdAt
            )
            if let workID = dto.workID {
                do {
                    if let work = try workCheck(workID) {
                        step.work = work
                    }
                } catch {
                    print("⚠️ [Backup:\(#function)] Failed to check work for step: \(error)")
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
                    print("⚠️ [Backup:\(#function)] Failed to check work for participant: \(error)")
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
            return session
        })
    }
}
