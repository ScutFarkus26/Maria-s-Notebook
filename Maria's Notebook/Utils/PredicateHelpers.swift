import Foundation
import CoreData

/// Helper functions for building common Core Data predicates.
/// These helpers reduce duplication and ensure consistent UUID-to-String conversion patterns.
enum PredicateHelpers {
    /// Creates a predicate for matching a work ID.
    static func workID(_ workID: UUID) -> NSPredicate {
        NSPredicate(format: "id == %@", workID as CVarArg)
    }

    /// Creates a predicate for matching a student ID in a LessonAssignment.
    static func studentID(_ studentID: UUID) -> NSPredicate {
        let idString = studentID.uuidString
        return NSPredicate(format: "studentIDs CONTAINS %@", idString)
    }

    /// Creates a predicate for matching multiple work IDs.
    static func workIDs(_ workIDs: Set<UUID>) -> NSPredicate {
        NSPredicate(format: "id IN %@", workIDs as CVarArg)
    }

    /// Creates a predicate for matching a lesson ID in a LessonAssignment.
    static func lessonID(_ lessonID: UUID) -> NSPredicate {
        let idString = lessonID.uuidString
        return NSPredicate(format: "lessonID == %@", idString)
    }
}
