import Foundation
import CoreData
import OSLog

// MARK: - CDTrackEntity/Group Imports

extension BackupEntityImporter {

    // MARK: - Tracks

    static func importTracks(
        _ dtos: [TrackDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDTrackEntity>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let t = CDTrackEntity(context: viewContext)
            t.id = dto.id
            t.title = dto.title
            t.createdAt = dto.createdAt
            return t
        })
    }

    // MARK: - CDTrackEntity Steps

    static func importTrackSteps(
        _ dtos: [TrackStepDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDTrackStepEntity>,
        trackCheck: EntityExistsCheck<CDTrackEntity>
    ) rethrows {
        var imported = 0
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let step = CDTrackStepEntity(context: viewContext)
            step.id = dto.id
            step.orderIndex = Int64(dto.orderIndex)
            step.lessonTemplateID = dto.lessonTemplateID
            step.createdAt = dto.createdAt
            if let trackID = dto.trackID {
                do {
                    if let track = try trackCheck(trackID) {
                        step.track = track
                    }
                } catch {
                    let desc = error.localizedDescription
                    Logger.backup.warning("Failed to check track for step: \(desc, privacy: .public)")
                }
            }
            viewContext.insert(step)
            imported += 1
        }
        if imported > 0 {
            // TrackStep is a shared-store entity. SharedStoreZoneRepair
            // will attach these to the CKShare after the import save —
            // log the count so post-restore zone repair has a baseline.
            Logger.backup.info(
                "Imported \(imported, privacy: .public) TrackStep record(s) from backup into shared store"
            )
        }
    }

    // MARK: - CDStudent CDTrackEntity Enrollments

    static func importStudentTrackEnrollments(
        _ dtos: [StudentTrackEnrollmentDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDStudentTrackEnrollmentEntity>,
        studentCheck: EntityExistsCheck<CDStudent>,
        trackCheck: EntityExistsCheck<CDTrackEntity>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let e = CDStudentTrackEnrollmentEntity(context: viewContext)
            e.id = dto.id
            e.createdAt = dto.createdAt
            e.studentID = dto.studentID
            e.trackID = dto.trackID
            e.startedAt = dto.startedAt
            e.isActive = dto.isActive
            // Set relationships for CloudKit zone assignment
            if let studentUUID = UUID(uuidString: dto.studentID) {
                e.student = try? studentCheck(studentUUID)
            }
            if let trackUUID = UUID(uuidString: dto.trackID) {
                e.track = try? trackCheck(trackUUID)
            }
            return e
        })
    }

    // MARK: - Group Tracks

    static func importSequenceTracks(
        _ dtos: [SequenceTrackDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDSequenceTrack>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let g = CDSequenceTrack(context: viewContext)
            g.id = dto.id
            g.area = dto.area
            g.sequence = dto.sequence
            g.isSequential = dto.isSequential
            g.isExplicitlyDisabled = dto.isExplicitlyDisabled
            g.createdAt = dto.createdAt
            return g
        })
    }
}
