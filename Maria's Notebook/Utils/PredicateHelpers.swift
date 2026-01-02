import Foundation
import SwiftData

/// Helper functions for building common SwiftData predicates, especially for CloudKit compatibility.
/// These helpers reduce duplication and ensure consistent UUID-to-String conversion patterns.
enum PredicateHelpers {
    /// Creates a predicate for matching a work ID (UUID stored as String in CloudKit).
    /// - Parameter workID: The work contract UUID
    /// - Returns: A predicate that matches the work ID
    static func workID(_ workID: UUID) -> Predicate<WorkContract> {
        #Predicate<WorkContract> { contract in
            contract.id == workID
        }
    }
    
    /// Creates a predicate for matching a student ID (UUID stored as String in CloudKit).
    /// - Parameter studentID: The student UUID
    /// - Returns: A predicate that matches the student ID
    static func studentID(_ studentID: UUID) -> Predicate<StudentLesson> {
        #Predicate<StudentLesson> { lesson in
            lesson.studentIDs.contains(studentID.cloudKitString)
        }
    }
    
    /// Creates a predicate for matching multiple work IDs.
    /// - Parameter workIDs: Set of work contract UUIDs
    /// - Returns: A predicate that matches any of the work IDs
    static func workIDs(_ workIDs: Set<UUID>) -> Predicate<WorkContract> {
        return #Predicate<WorkContract> { contract in
            workIDs.contains(contract.id)
        }
    }
    
    /// Creates a predicate for matching a lesson ID (UUID stored as String in CloudKit).
    /// - Parameter lessonID: The lesson UUID
    /// - Returns: A predicate that matches the lesson ID
    static func lessonID(_ lessonID: UUID) -> Predicate<StudentLesson> {
        #Predicate<StudentLesson> { lesson in
            lesson.lessonID == lessonID.cloudKitString
        }
    }
}


