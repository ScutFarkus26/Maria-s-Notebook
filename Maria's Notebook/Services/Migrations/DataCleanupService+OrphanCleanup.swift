import Foundation
import SwiftData
import os

// MARK: - Orphan Cleanup

extension DataCleanupService {

    // MARK: - Orphaned Student ID Cleanup

    /// Cleans orphaned student IDs from LessonAssignment records.
    /// Removes student IDs that no longer exist in the database to maintain referential integrity
    /// when using manual ID management instead of SwiftData relationships.
    /// Safe to call repeatedly - it's idempotent and only removes non-existent IDs.
    static func cleanOrphanedStudentIDs(using context: ModelContext) async {
        // Fetch all students to build valid ID set
        let studentFetch = FetchDescriptor<Student>()
        let allStudents = context.safeFetch(studentFetch)

        // Guard against empty student list - if fetch failed, bail out to prevent mass deletion
        guard !allStudents.isEmpty else {
            logger.warning("cleanOrphanedStudentIDs: No students found - skipping cleanup to prevent data loss")
            return
        }

        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })

        let laFetch = FetchDescriptor<LessonAssignment>()
        let allLAs = context.safeFetch(laFetch)

        var cleaned = 0
        for (index, la) in allLAs.enumerated() {
            if index % 100 == 0 { await Task.yield() }

            let originalIDs = la.studentIDs
            let cleanedIDs = originalIDs.filter { validStudentIDs.contains($0) }

            if cleanedIDs.count != originalIDs.count {
                la.studentIDs = cleanedIDs
                la.students = la.students.filter { student in
                    validStudentIDs.contains(student.cloudKitKey)
                }
                cleaned += 1
            }
        }

        if cleaned > 0 {
            context.safeSave()
        }
    }

    /// Cleans orphaned student IDs from WorkModel records.
    /// Removes student IDs that no longer exist in the database to maintain referential integrity
    /// when using manual ID management instead of SwiftData relationships.
    /// Safe to call repeatedly - it's idempotent and only removes non-existent IDs.
    static func cleanOrphanedWorkStudentIDs(using context: ModelContext) async {
        // Fetch all students to build valid ID set
        let studentFetch = FetchDescriptor<Student>()
        let allStudents = context.safeFetch(studentFetch)

        // Guard against empty student list - if fetch failed, bail out to prevent mass deletion
        guard !allStudents.isEmpty else {
            logger.warning("cleanOrphanedWorkStudentIDs: No students found - skipping cleanup to prevent data loss")
            return
        }

        let validStudentIDs = Set(allStudents.map { $0.id.uuidString })

        // Fetch all WorkModels
        let workFetch = FetchDescriptor<WorkModel>()
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
            if let participants = work.participants, !participants.isEmpty {
                let validParticipants = participants.filter { participant in
                    validStudentIDs.contains(participant.studentID)
                }

                if validParticipants.count != participants.count {
                    work.participants = validParticipants.isEmpty ? nil : validParticipants
                    // Delete orphaned participants from context
                    for participant in participants where !validStudentIDs.contains(participant.studentID) {
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
