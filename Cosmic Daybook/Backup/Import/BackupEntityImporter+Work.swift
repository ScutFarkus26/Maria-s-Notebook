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
        existing: ExistingLookup<CDWorkModel>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
                let work = current ?? CDWorkModel(context: viewContext)
                work.id = dto.id
                work.title = dto.title
                work.workTypeRaw = dto.workTypeRaw
                work.kindRaw = dto.kindRaw
                work.studentLessonID = dto.studentLessonID
                work.createdAt = dto.createdAt
                work.completedAt = dto.completedAt
                // Older backups carry `complete` + an outcome; fold them the way the launch repair does.
                work.statusRaw = WorkStatusMigration.mergedStatus(
                    statusRaw: dto.statusRaw, outcomeRaw: dto.completionOutcomeRaw
                ).rawValue
                work.assignedAt = dto.assignedAt
                work.lastTouchedAt = dto.lastTouchedAt
                work.dueAt = dto.dueAt
                work.completionOutcomeRaw = dto.completionOutcomeRaw
                work.studentID = dto.studentID
                work.lessonID = dto.lessonID
                work.presentationID = dto.presentationID
                work.trackID = dto.trackID
                work.trackStepID = dto.trackStepID
                work.scheduledNote = dto.scheduledNote
                work.scheduledReasonRaw = dto.scheduledReasonRaw
                work.sourceContextTypeRaw = dto.sourceContextTypeRaw
                work.sourceContextID = dto.sourceContextID
                work.sampleWorkID = dto.sampleWorkID
                work.checkInStyleRaw = dto.checkInStyleRaw
                work.restingUntil = dto.restingUntil
                return work
            })
    }

    // MARK: - Work Completion Records

    /// Imports work completion records from DTOs.
    static func importWorkCompletionRecords(
        _ dtos: [WorkCompletionRecordDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDWorkCompletionRecord>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
            let r = current ?? CDWorkCompletionRecord(context: viewContext)
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
        existing: ExistingLookup<CDWorkCheckIn>,
        workCheck: EntityLookup<CDWorkModel>
    ) rethrows {
        for dto in dtos {
            guard let workUUID = UUID(uuidString: dto.workID) else { continue }
            let checkIn = existingEntity(id: dto.id, existing: existing) ?? CDWorkCheckIn(context: viewContext)
            checkIn.id = dto.id
            checkIn.workID = dto.workID
            checkIn.date = dto.date
            checkIn.statusRaw = (WorkCheckInStatus(rawValue: dto.statusRaw) ?? .scheduled).rawValue
            checkIn.purpose = dto.purpose
            // A row from before the flag (v19) has none: a check-in already here keeps its own.
            if let initiated = dto.studentInitiated { checkIn.studentInitiated = initiated }
            // Likewise the duration (schema 23): an older row says nothing about it.
            if let minutes = dto.durationMinutes { checkIn.durationMinutesValue = minutes }
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

    // MARK: - Work Participants

    static func importWorkParticipants(
        _ dtos: [WorkParticipantEntityDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDWorkParticipantEntity>,
        workCheck: EntityLookup<CDWorkModel>
    ) rethrows {
        for dto in dtos {
            guard UUID(uuidString: dto.studentID) != nil else { continue }
            let participant = existingEntity(id: dto.id, existing: existing) ?? CDWorkParticipantEntity(context: viewContext)
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
}
