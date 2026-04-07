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

    static func importGroupTracks(
        _ dtos: [GroupTrackDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDGroupTrack>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
            let g = CDGroupTrack(context: viewContext)
            g.id = dto.id
            g.subject = dto.subject
            g.group = dto.group
            g.isSequential = dto.isSequential
            g.isExplicitlyDisabled = dto.isExplicitlyDisabled
            g.createdAt = dto.createdAt
            return g
        })
    }
}
