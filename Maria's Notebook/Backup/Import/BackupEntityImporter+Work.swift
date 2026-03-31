import Foundation
import CoreData
import OSLog

// MARK: - Work

extension BackupEntityImporter {

    // MARK: - CDWorkModel

    /// Imports CDWorkModel records from DTOs. Must run BEFORE child entities (check-ins, steps, participants).
    static func importWorkModels(
        _ dtos: [WorkModelDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDWorkModel>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let work = CDWorkModel(context: viewContext)
                work.id = dto.id
                work.title = dto.title
                work.kindRaw = dto.kindRaw
                work.studentLessonID = dto.studentLessonID
                work.createdAt = dto.createdAt
                work.completedAt = dto.completedAt
                work.statusRaw = (WorkStatus(rawValue: dto.statusRaw) ?? .active).rawValue
                work.assignedAt = dto.assignedAt
                work.lastTouchedAt = dto.lastTouchedAt
                work.dueAt = dto.dueAt
                work.completionOutcomeRaw = dto.completionOutcomeRaw
                work.legacyContractID = dto.legacyContractID
                work.studentID = dto.studentID
                work.lessonID = dto.lessonID
                work.presentationID = dto.presentationID
                work.trackID = dto.trackID
                work.trackStepID = dto.trackStepID
                work.scheduledNote = dto.scheduledNote
                work.scheduledReasonRaw = dto.scheduledReasonRaw
                work.sourceContextTypeRaw = dto.sourceContextTypeRaw
                work.sourceContextID = dto.sourceContextID
                work.legacyStudentLessonID = dto.legacyStudentLessonID
                work.sampleWorkID = dto.sampleWorkID
                work.checkInStyleRaw = dto.checkInStyleRaw
                return work
            })
    }

    // MARK: - Work Completion Records

    /// Imports work completion records from DTOs.
    static func importWorkCompletionRecords(
        _ dtos: [WorkCompletionRecordDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDWorkCompletionRecord>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let r = CDWorkCompletionRecord(context: viewContext)
            r.id = dto.id
            r.workID = dto.workID.uuidString
            r.studentID = dto.studentID.uuidString
            r.completedAt = dto.completedAt
            return r
        })
    }

    // MARK: - Work Check-Ins

    static func importWorkCheckIns(
        _ dtos: [WorkCheckInDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDWorkCheckIn>,
        workCheck: EntityExistsCheck<CDWorkModel>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard let workUUID = UUID(uuidString: dto.workID) else { continue }
            let checkIn = CDWorkCheckIn(context: viewContext)
            checkIn.id = dto.id
            checkIn.workID = dto.workID
            checkIn.date = dto.date
            checkIn.statusRaw = (WorkCheckInStatus(rawValue: dto.statusRaw) ?? .scheduled).rawValue
            checkIn.purpose = dto.purpose
            // Link to work if exists
            do {
                if let work = try workCheck(workUUID) {
                    checkIn.work = work
                }
            } catch {
                let desc = error.localizedDescription
                Logger.backup.warning("Failed to check work for check-in: \(desc, privacy: .public)")
            }
            viewContext.insert(checkIn)
        }
    }

    // MARK: - Work Steps

    static func importWorkSteps(
        _ dtos: [WorkStepDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDWorkStep>,
        workCheck: EntityExistsCheck<CDWorkModel>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let step = CDWorkStep(context: viewContext)
            step.id = dto.id
            step.orderIndex = Int64(dto.orderIndex)
            step.title = dto.title
            step.instructions = dto.instructions
            step.completedAt = dto.completedAt
            step.notes = dto.notes
            step.completionOutcomeRaw = dto.completionOutcomeRaw
            step.createdAt = dto.createdAt
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
            viewContext.insert(step)
        }
    }

    // MARK: - Work Participants

    static func importWorkParticipants(
        _ dtos: [WorkParticipantEntityDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<WorkParticipantEntity>,
        workCheck: EntityExistsCheck<CDWorkModel>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            guard UUID(uuidString: dto.studentID) != nil else { continue }
            let participant = WorkParticipantEntity(context: viewContext)
            participant.id = dto.id
            participant.studentID = dto.studentID
            participant.completedAt = dto.completedAt
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
            viewContext.insert(participant)
        }
    }

    // MARK: - Practice Sessions

    static func importPracticeSessions(
        _ dtos: [PracticeSessionDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDPracticeSession>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let session = CDPracticeSession(context: viewContext)
            session.id = dto.id
            session.createdAt = dto.createdAt
            session.date = dto.date
            session.duration = dto.duration ?? 0
            session.studentIDs = dto.studentIDs as NSObject
            session.workItemIDs = dto.workItemIDs as NSObject
            session.sharedNotes = dto.sharedNotes
            session.location = dto.location
            session.practiceQuality = Int64(dto.practiceQuality ?? 0)
            session.independenceLevel = Int64(dto.independenceLevel ?? 0)
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
