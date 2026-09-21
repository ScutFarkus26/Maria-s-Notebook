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

    private static func mergeStudent(canonical: CDStudent, duplicate: CDStudent) {
        if canonical.firstName.isEmpty { canonical.firstName = duplicate.firstName }
        if canonical.lastName.isEmpty { canonical.lastName = duplicate.lastName }
        if canonical.nickname == nil { canonical.nickname = duplicate.nickname }
        if canonical.dateStarted == nil { canonical.dateStarted = duplicate.dateStarted }
        if canonical.previousLevelRaw == nil { canonical.previousLevelRaw = duplicate.previousLevelRaw }
        if canonical.dateLastPromoted == nil { canonical.dateLastPromoted = duplicate.dateLastPromoted }
        if canonical.manualOrder == 0 && duplicate.manualOrder != 0 { canonical.manualOrder = duplicate.manualOrder }

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
