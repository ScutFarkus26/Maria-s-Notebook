import Foundation
import SwiftData

/// Helper functions for building common SwiftData predicates, especially for CloudKit compatibility.
/// These helpers reduce duplication and ensure consistent UUID-to-String conversion patterns.
enum PredicateHelpers {
    /// Creates a predicate for matching a work ID (UUID stored as String in CloudKit).
    /// - Parameter workID: The work model UUID
    /// - Returns: A predicate that matches the work ID
    static func workID(_ workID: UUID) -> Predicate<WorkModel> {
        #Predicate<WorkModel> { work in
            work.id == workID
        }
    }
    
    /// Creates a predicate for matching a student ID (UUID stored as String in CloudKit).
    /// - Parameter studentID: The student UUID
    /// - Returns: A predicate that matches the student ID
    static func studentID(_ studentID: UUID) -> Predicate<StudentLesson> {
        let idString = studentID.cloudKitString
        return #Predicate<StudentLesson> { lesson in
            lesson.studentIDs.contains(idString)
        }
    }
    
    /// Creates a predicate for matching multiple work IDs.
    /// - Parameter workIDs: Set of work model UUIDs
    /// - Returns: A predicate that matches any of the work IDs
    static func workIDs(_ workIDs: Set<UUID>) -> Predicate<WorkModel> {
        return #Predicate<WorkModel> { work in
            workIDs.contains(work.id)
        }
    }
    
    /// Creates a predicate for matching a lesson ID (UUID stored as String in CloudKit).
    /// - Parameter lessonID: The lesson UUID
    /// - Returns: A predicate that matches the lesson ID
    static func lessonID(_ lessonID: UUID) -> Predicate<StudentLesson> {
        let idString = lessonID.cloudKitString
        return #Predicate<StudentLesson> { lesson in
            lesson.lessonID == idString
        }
    }
}

