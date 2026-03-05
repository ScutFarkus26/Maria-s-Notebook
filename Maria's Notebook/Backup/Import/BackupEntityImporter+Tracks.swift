import Foundation
import SwiftData

// MARK: - Track/Group Imports

extension BackupEntityImporter {

    // MARK: - Tracks

    static func importTracks(_ dtos: [TrackDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<Track>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let t = Track()
            t.id = dto.id
            t.title = dto.title
            t.createdAt = dto.createdAt
            return t
        }
    }

    // MARK: - Track Steps

    static func importTrackSteps(
        _ dtos: [TrackStepDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<TrackStep>,
        trackCheck: EntityExistsCheck<Track>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let step = TrackStep()
            step.id = dto.id
            step.orderIndex = dto.orderIndex
            step.lessonTemplateID = dto.lessonTemplateID
            step.createdAt = dto.createdAt
            if let trackID = dto.trackID {
                do {
                    if let track = try trackCheck(trackID) {
                        step.track = track
                    }
                } catch {
                    print("\u{26a0}\u{fe0f} [Backup:\(#function)] Failed to check track for step: \(error)")
                }
            }
            modelContext.insert(step)
        }
    }

    // MARK: - Student Track Enrollments

    static func importStudentTrackEnrollments(_ dtos: [StudentTrackEnrollmentDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<StudentTrackEnrollment>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let e = StudentTrackEnrollment()
            e.id = dto.id
            e.createdAt = dto.createdAt
            e.studentID = dto.studentID
            e.trackID = dto.trackID
            e.startedAt = dto.startedAt
            e.isActive = dto.isActive
            return e
        }
    }

    // MARK: - Group Tracks

    static func importGroupTracks(_ dtos: [GroupTrackDTO], into modelContext: ModelContext, existingCheck: EntityExistsCheck<GroupTrack>) rethrows {
        try importSimpleEntities(dtos, into: modelContext, existingCheck: existingCheck, idExtractor: { $0.id }) { dto in
            let g = GroupTrack(
                id: dto.id,
                subject: dto.subject,
                group: dto.group,
                isSequential: dto.isSequential,
                isExplicitlyDisabled: dto.isExplicitlyDisabled,
                createdAt: dto.createdAt
            )
            return g
        }
    }
}
