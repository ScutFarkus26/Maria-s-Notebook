import CoreData
import Foundation
@testable import CosmicDaybook

/// The three launch repairs as they were until 2026-09-26, kept verbatim so
/// `LaunchRepairPassTests` can check the background pass against them. The
/// bootstrapper awaited them on the main actor with the view context; each
/// yielded every 100 rows and saved the view context when it changed a row.
@MainActor
enum LaunchRepairOldCode {

    /// `DataCleanupService.repairScheduledForDayMirror`.
    static func repairScheduledForDayMirror(using context: NSManagedObjectContext) async {
        let fetch = CDFetchRequest(CDLessonAssignment.self)
        let assignments = context.safeFetch(fetch)
        var repaired = 0

        for (index, la) in assignments.enumerated() {
            if index % 100 == 0 { await Task.yield() }

            let correctMirror = la.scheduledFor.map(AppCalendar.startOfDay) ?? Date.distantPast
            if la.scheduledForDay != correctMirror {
                la.scheduledForDay = correctMirror
                repaired += 1
            }
        }

        if repaired > 0 {
            context.safeSave()
        }
    }

    /// `DataCleanupService.cleanOrphanedStudentIDs`.
    static func cleanOrphanedStudentIDs(using context: NSManagedObjectContext) async {
        // Fetch all students to build valid ID set
        let studentFetch = CDFetchRequest(CDStudent.self)
        let allStudents = context.safeFetch(studentFetch)

        // Guard against empty student list - if fetch failed, bail out to prevent mass deletion
        guard !allStudents.isEmpty else { return }

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

    /// `DataCleanupService.cleanOrphanedWorkStudentIDs`.
    static func cleanOrphanedWorkStudentIDs(using context: NSManagedObjectContext) async {
        // Fetch all students to build valid ID set
        let studentFetch = CDFetchRequest(CDStudent.self)
        let allStudents = context.safeFetch(studentFetch)

        // Guard against empty student list - if fetch failed, bail out to prevent mass deletion
        guard !allStudents.isEmpty else { return }

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
