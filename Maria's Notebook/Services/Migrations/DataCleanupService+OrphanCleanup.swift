import Foundation
import CoreData
import os

// MARK: - Orphan Cleanup

extension DataCleanupService {

    // MARK: - Orphaned CDStudent ID Cleanup

    /// Cleans orphaned student IDs from CDLessonAssignment records.
    /// Removes student IDs that no longer exist in the database to maintain referential integrity
    /// when using manual ID management instead of Core Data relationships.
    /// Safe to call repeatedly - it's idempotent and only removes non-existent IDs.
    static func cleanOrphanedStudentIDs(using context: NSManagedObjectContext) async {
        // Fetch all students to build valid ID set
        let studentFetch = CDFetchRequest(CDStudent.self)
        let allStudents = context.safeFetch(studentFetch)

        // Guard against empty student list - if fetch failed, bail out to prevent mass deletion
        guard !allStudents.isEmpty else {
            logger.info("cleanOrphanedStudentIDs: No students found - skipping cleanup to prevent data loss")
            return
        }

        let validStudentIDs = Set(allStudents.map { ($0.id ?? UUID()).uuidString })

        let laFetch = CDFetchRequest(CDLessonAssignment.self)
        let allLAs = context.safeFetch(laFetch)

        var cleaned = 0
        for (index, la) in allLAs.enumerated() {
            if index % 100 == 0 { await Task.yield() }

            let originalIDs = la.studentIDs
            let cleanedIDs = originalIDs.filter { validStudentIDs.contains($0) }

            if cleanedIDs.count != originalIDs.count {
                la.studentIDs = cleanedIDs
                cleaned += 1
            }
        }

        if cleaned > 0 {
            context.safeSave()
        }
    }

    /// Cleans orphaned student IDs from CDWorkModel records.
    /// Removes student IDs that no longer exist in the database to maintain referential integrity
    /// when using manual ID management instead of Core Data relationships.
    /// Safe to call repeatedly - it's idempotent and only removes non-existent IDs.
    static func cleanOrphanedWorkStudentIDs(using context: NSManagedObjectContext) async {
        // Fetch all students to build valid ID set
        let studentFetch = CDFetchRequest(CDStudent.self)
        let allStudents = context.safeFetch(studentFetch)

        // Guard against empty student list - if fetch failed, bail out to prevent mass deletion
        guard !allStudents.isEmpty else {
            logger.info("cleanOrphanedWorkStudentIDs: No students found - skipping cleanup to prevent data loss")
            return
        }

        let validStudentIDs = Set(allStudents.map { ($0.id ?? UUID()).uuidString })

        // Fetch all WorkModels
        let workFetch = CDFetchRequest(CDWorkModel.self)
        let allWorks = context.safeFetch(workFetch)

        var cleaned = 0
        for (index, work) in allWorks.enumerated() {
            // Yield every 100 iterations to prevent blocking
            if index % 100 == 0 { await Task.yield() }

            var modified = false

            // Check work.studentID - if not empty and not in valid set, clear it
            if !work.studentID.isEmpty && !validStudentIDs.contains(work.studentID) {
                work.studentID = ""
                modified = true
            }

            // Check work.participants - remove any with orphaned studentIDs
            if let participantsSet = work.participants as? Set<CDWorkParticipantEntity>, !participantsSet.isEmpty {
                let orphanedParticipants = participantsSet.filter { !validStudentIDs.contains($0.studentID) }

                if !orphanedParticipants.isEmpty {
                    for participant in orphanedParticipants {
                        context.delete(participant)
                    }
                    modified = true
                }
            }

            if modified {
                cleaned += 1
            }
        }

        if cleaned > 0 {
            context.safeSave()
        }
    }
}
