import Foundation

/// The three requests ParentLocker's own attendance page makes, which are all
/// the app needs: the course list, a class's roster for a day, and a class's
/// save. `ParentLockerHTTP` makes them over the network with the person's
/// sign-in cookies; tests use a fake. Each throws a `ParentLockerError`.
nonisolated protocol ParentLockerTransport: Sendable {
    /// The teacher's classes, read from the attendance page.
    func courses() async throws -> [ParentLockerCourse]
    /// A class's roster and marks for `date`.
    func roster(course: ParentLockerCourse, date: Date) async throws -> ParentLockerRoster
    /// Saves one class's changes.
    func save(batch: ParentLockerPlanner.Batch) async throws -> ParentLockerSaveReply
}
