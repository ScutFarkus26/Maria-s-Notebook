import Foundation
import CoreData

nonisolated extension CDStudent {
    /// Canonical predicate for today's roster fetches: the children who haven't
    /// left the class (`hasLeft(by:)`). Use with `@FetchRequest` or `NSFetchRequest`.
    /// A child whose last day is still to come is on it through that day, as she
    /// is on the attendance roll (domain logic review R7). Built for today each
    /// time it is read.
    static var enrolledPredicate: NSPredicate { notLeftPredicate(by: Date()) }
}

extension Sequence where Element == CDStudent {
    /// Drops children who have left the class by today (`hasLeft(by:)`): a
    /// departed child stays through her last day. Use when filtering post-fetch;
    /// prefer `CDStudent.enrolledPredicate` at fetch time when possible.
    func filterEnrolled(now: Date = Date()) -> [CDStudent] {
        filter { !$0.hasLeft(by: now) }
    }

    /// Produces the active roster: drops former students, removes CloudKit duplicate-ID
    /// artifacts, and hides configured test students unless `showTest` is true.
    func visibleRoster(showTest: Bool, testNames: String) -> [CDStudent] {
        TestStudentsFilter.filterVisible(
            Array(self).filterEnrolled().uniqueByID,
            show: showTest,
            namesRaw: testNames
        )
    }
}
