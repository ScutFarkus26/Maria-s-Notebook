import Foundation
import CoreData
import CloudKit
import os

// MARK: - Deduplicate Students

nonisolated extension DataCleanupService {
    @discardableResult
    static func deduplicateStudentsStrong(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer? = nil,
        scope: DeduplicationScope = .everything
    ) -> Int {
        deduplicate(CDStudent.self, using: context, container: container, scope: scope, merge: mergeStudent)
    }

    /// Track enrollments are left alone: they name their student by
    /// `studentID`, which the surviving copy shares. (Before schema 9 the
    /// duplicate's enrollments went with it by cascade, taking the child's
    /// real enrollment rows along.)
    private static func mergeStudent(canonical: CDStudent, duplicate: CDStudent) {
        if canonical.firstName.isEmpty { canonical.firstName = duplicate.firstName }
        if canonical.lastName.isEmpty { canonical.lastName = duplicate.lastName }
        if canonical.nickname == nil { canonical.nickname = duplicate.nickname }
        mergeChoices(canonical: canonical, duplicate: duplicate)
        if canonical.dateStarted == nil { canonical.dateStarted = duplicate.dateStarted }
        if canonical.previousLevelRaw == nil { canonical.previousLevelRaw = duplicate.previousLevelRaw }
        if canonical.dateLastPromoted == nil { canonical.dateLastPromoted = duplicate.dateLastPromoted }
        if canonical.manualOrder == 0 && duplicate.manualOrder != 0 { canonical.manualOrder = duplicate.manualOrder }
        mergeStudentLinks(canonical: canonical, duplicate: duplicate)
    }

    /// The ParentLocker match (schema 18) and "Born after sunset" (schema 21),
    /// where clearing one is a choice, not a gap: the copy changed last
    /// decides, so a match or switch cleared on it stays cleared (an older
    /// copy still holding one brought it back; bug hunt 2026-10-29). Copies
    /// changed in the same millisecond (as CloudKit keeps it: `millisecondKey`),
    /// or either with no date, can't say which is newer: then a match on
    /// either keeps the child matched, so sends still go by ID, and either
    /// saying "after sunset" keeps her Hebrew birthday on the right day, as a
    /// copy from a backup older than the field holds neither.
    private static func mergeChoices(canonical: CDStudent, duplicate: CDStudent) {
        if let kept = millisecondKey(canonical.modifiedAt), let other = millisecondKey(duplicate.modifiedAt),
           kept != other {
            guard other > kept else { return }
            canonical.parentLockerID = duplicate.parentLockerID
            canonical.bornAfterSunset = duplicate.bornAfterSunset
            // Its date too, so a third copy is weighed against the newest.
            canonical.modifiedAt = duplicate.modifiedAt
            return
        }
        if canonical.parentLockerID?.isEmpty ?? true, let matched = duplicate.parentLockerID, !matched.isEmpty {
            canonical.parentLockerID = matched
        }
        if duplicate.bornAfterSunset && !canonical.bornAfterSunset { canonical.bornAfterSunset = true }
    }

    /// The duplicate's next lessons and documents, onto the canonical copy.
    private static func mergeStudentLinks(canonical: CDStudent, duplicate: CDStudent) {
        // nextLessons is a Transformable [String] stored as NSObject
        let canonicalNext = canonical.nextLessonsArray
        let duplicateNext = duplicate.nextLessonsArray
        if canonicalNext.isEmpty && !duplicateNext.isEmpty {
            canonical.nextLessons = duplicateNext as NSObject
        } else if !canonicalNext.isEmpty && !duplicateNext.isEmpty {
            let merged = Array(Set(canonicalNext).union(duplicateNext))
            canonical.nextLessons = merged as NSObject
        }

        // Re-point duplicate's documents to canonical student via FK
        let existingDocIDs = Set(canonical.documents.compactMap(\.id))
        for doc in duplicate.documents where doc.id == nil || !existingDocIDs.contains(doc.id!) {
            doc.student = canonical
        }
    }
}
