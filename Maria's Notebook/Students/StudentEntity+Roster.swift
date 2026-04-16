import Foundation
import CoreData

extension CDStudent {
    /// Canonical predicate for active-roster fetches. Use with `@FetchRequest` or `NSFetchRequest`
    /// to exclude withdrawn students at the Core Data layer.
    nonisolated(unsafe) static let enrolledPredicate = NSPredicate(
        format: "enrollmentStatusRaw == %@",
        EnrollmentStatus.enrolled.rawValue
    )
}

extension Sequence where Element == CDStudent {
    /// Drops withdrawn students. Use when filtering post-fetch; prefer `CDStudent.enrolledPredicate`
    /// at fetch time when possible.
    func filterEnrolled() -> [CDStudent] {
        filter(\.isEnrolled)
    }

    /// Produces the active roster: drops withdrawn students, removes CloudKit duplicate-ID
    /// artifacts, and hides configured test students unless `showTest` is true.
    func visibleRoster(showTest: Bool, testNames: String) -> [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(self).filterEnrolled().uniqueByID,
            show: showTest,
            namesRaw: testNames
        )
    }
}
