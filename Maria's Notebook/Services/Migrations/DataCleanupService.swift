import Foundation
import CoreData
import OSLog

// MARK: - Data Cleanup Service

/// Service responsible for cleaning up orphaned data and maintaining referential integrity.
/// Handles cleanup of orphaned student IDs, duplicate records, and other data integrity issues.
enum DataCleanupService {
    static let logger = Logger.migration

    // MARK: - Run All Cleanup Operations

    /// Runs all data cleanup operations in sequence.
    /// Safe to call repeatedly - each operation is idempotent.
    static func runAllCleanupOperations(using context: NSManagedObjectContext) async {
        // Run comprehensive deduplication first since other cleanups depend on valid data
        _ = deduplicateAllModels(using: context)
        await cleanOrphanedStudentIDs(using: context)
        await cleanOrphanedWorkStudentIDs(using: context)
        deduplicateDraftLessonAssignments(using: context)
        await repairScopeForContextualNotes(using: context)
        await repairDenormalizedScheduledForDay(using: context)
        backfillTrackEnrollmentRelationships(using: context)
    }

    // MARK: - Track Enrollment Relationship Backfill

    /// Backfills student/track relationships on StudentTrackEnrollment records
    /// that were created before relationships were added to the model.
    /// Required for CloudKit zone assignment in the shared store.
    static func backfillTrackEnrollmentRelationships(using context: NSManagedObjectContext) {
        let enrollments = context.safeFetch(CDFetchRequest(CDStudentTrackEnrollmentEntity.self))
        let needsBackfill = enrollments.filter { $0.student == nil || $0.track == nil }
        guard !needsBackfill.isEmpty else { return }

        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        let tracks = context.safeFetch(CDFetchRequest(CDTrackEntity.self))

        let studentsByID = Dictionary(uniqueKeysWithValues: students.compactMap { s in
            s.id.map { ($0.uuidString, s) }
        })
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.compactMap { t in
            t.id.map { ($0.uuidString, t) }
        })

        var repaired = 0
        for enrollment in needsBackfill {
            if enrollment.student == nil {
                enrollment.student = studentsByID[enrollment.studentID]
            }
            if enrollment.track == nil {
                enrollment.track = tracksByID[enrollment.trackID]
            }
            repaired += 1
        }

        // Also backfill GroupTrack → Track relationships
        let groupTracks = context.safeFetch(CDFetchRequest(CDGroupTrackEntity.self))
        let orphanedGroupTracks = groupTracks.filter { $0.track == nil }
        for groupTrack in orphanedGroupTracks {
            let title = "\(groupTrack.subject) — \(groupTrack.group)"
            if let matchingTrack = tracks.first(where: { $0.title.trimmed() == title }) {
                groupTrack.track = matchingTrack
                repaired += 1
            }
        }

        if repaired > 0 {
            context.safeSave()
            logger.info("Backfilled relationships on \(repaired, privacy: .public) track-related record(s)")
        }
    }
}
