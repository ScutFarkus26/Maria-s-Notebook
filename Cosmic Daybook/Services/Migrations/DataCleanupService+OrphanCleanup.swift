import Foundation
import CoreData
import os

// MARK: - Orphan Cleanup

// The launch pass (`MigrationRunner.runPass`) calls these on a background
// context, inside its `perform`: they are synchronous and must run on the
// context's own queue. They used to run on the main-actor view context,
// yielding every 100 rows.

nonisolated extension DataCleanupService {

    // MARK: - Orphaned CDStudent ID Cleanup

    /// Cleans orphaned student IDs from CDLessonAssignment records.
    /// Removes student IDs that no longer exist in the database to maintain referential integrity
    /// when using manual ID management instead of Core Data relationships.
    /// Safe to call repeatedly - it's idempotent and only removes non-existent IDs.
    /// - Parameter grace: when given, an id is only removed once it has been missing long
    ///   enough (`OrphanStudentGrace`); nil removes every missing id at once.
    static func cleanOrphanedStudentIDs(using context: NSManagedObjectContext, grace: OrphanStudentGrace? = nil) {
        // Guard against an empty student list - if fetch failed, bail out to prevent mass deletion
        guard let validStudentIDs = studentIDStrings(using: context) else {
            logger.info("cleanOrphanedStudentIDs: No students found - skipping cleanup to prevent data loss")
            return
        }

        let laFetch = CDFetchRequest(CDLessonAssignment.self)
        let allLAs = context.safeFetch(laFetch)

        let missing = Set(allLAs.flatMap(\.studentIDs)).subtracting(validStudentIDs)
        let removable = grace?.admit(missing: missing, validIDs: validStudentIDs) ?? missing

        var cleaned = 0
        for la in allLAs {
            let originalIDs = la.studentIDs
            let cleanedIDs = originalIDs.filter { !removable.contains($0) }

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
    /// - Returns: How many work rows it changed.
    /// - Parameter grace: when given, an id is only cleared once it has been missing long
    ///   enough (`OrphanStudentGrace`); nil clears every missing id at once.
    @discardableResult
    static func cleanOrphanedWorkStudentIDs(
        using context: NSManagedObjectContext, grace: OrphanStudentGrace? = nil
    ) -> Int {
        // Guard against an empty student list - if fetch failed, bail out to prevent mass deletion
        guard let validStudentIDs = studentIDStrings(using: context) else {
            logger.info("cleanOrphanedWorkStudentIDs: No students found - skipping cleanup to prevent data loss")
            return 0
        }

        let allWorks = context.safeFetch(orphanCleanupWorkFetch())

        let missing = studentIDsNamed(by: allWorks).subtracting(validStudentIDs)
        let removable = grace?.admit(missing: missing, validIDs: validStudentIDs) ?? missing

        var cleaned = 0
        for work in allWorks {
            var modified = false

            // Check work.studentID - if not empty and missing long enough, clear it
            if !work.studentID.isEmpty && removable.contains(work.studentID) {
                work.studentID = ""
                modified = true
            }

            // Check work.participants - remove any whose student is missing long enough
            if let participantsSet = work.participants as? Set<CDWorkParticipantEntity>, !participantsSet.isEmpty {
                let orphanedParticipants = participantsSet.filter { removable.contains($0.studentID) }

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
        return cleaned
    }

    /// Every student id the rows name, as owner or participant.
    private static func studentIDsNamed(by works: [CDWorkModel]) -> Set<String> {
        var named = Set<String>()
        for work in works {
            if !work.studentID.isEmpty { named.insert(work.studentID) }
            for participant in (work.participants as? Set<CDWorkParticipantEntity>) ?? [] {
                named.insert(participant.studentID)
            }
        }
        return named
    }

    /// Every work row, with its participants loaded by one batched prefetch
    /// alongside the fetch. Without it the cleanup fired the `participants`
    /// fault once per row — one SELECT per work.
    static func orphanCleanupWorkFetch() -> NSFetchRequest<CDWorkModel> {
        let request = CDFetchRequest(CDWorkModel.self)
        request.relationshipKeyPathsForPrefetching = ["participants"]
        return request
    }

    // MARK: - Student IDs

    /// The `uuidString` of every student's `id` — the form work and assignment
    /// rows store — or nil when there are no students (or they can't be read),
    /// which both cleanups treat as "touch nothing".
    ///
    /// Reads the one column rather than materialising students. A dictionary
    /// fetch answers from the store and ignores the context's unsaved changes,
    /// so a context that has some, or a read that finds no rows, falls back to
    /// the object fetch the cleanups used before. A student with no `id` adds
    /// nothing (it used to add a fresh random UUID, which matches nothing).
    static func studentIDStrings(using context: NSManagedObjectContext) -> Set<String>? {
        if !context.hasChanges, let ids = storedStudentIDStrings(using: context) {
            return ids
        }
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        guard !students.isEmpty else { return nil }
        return Set(students.compactMap { $0.id?.uuidString })
    }

    /// The ids as one column from the store, or nil when that read found no
    /// rows or failed.
    private static func storedStudentIDStrings(using context: NSManagedObjectContext) -> Set<String>? {
        guard let entityName = CDFetchRequest(CDStudent.self).entityName else { return nil }
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        guard let rows = try? context.fetch(request), !rows.isEmpty else { return nil }
        return Set(rows.compactMap { ($0["id"] as? UUID)?.uuidString })
    }
}
