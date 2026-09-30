import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// While a record moves out of the classroom share, a device can hold two copies of it: the
/// shared original and the private copy. The dedup passes must delete neither, or the move's
/// own delete of the original could leave no copy anywhere (`DedupShareBoundary`).
@Suite("Dedup across the share boundary")
@MainActor
struct DedupShareBoundaryTests {

    private let shareZone = "com.apple.coredata.cloudkit.share.DB5879EF-D0F4-467E-A1EA-E51092B48BD7"
    private let defaultZone = "com.apple.coredata.cloudkit.zone"

    /// Runs `body` with `shared` reported in the share zone and every other record outside.
    private func withZones<T>(shared: Set<NSManagedObjectID>, _ body: () throws -> T) rethrows -> T {
        let shareZone = shareZone
        let defaultZone = defaultZone
        return try DedupShareBoundary.$zoneNameOverride.withValue({ id in
            shared.contains(id) ? shareZone : defaultZone
        }, operation: body)
    }

    @Test("Two copies of a student, one shared and one not, are both kept")
    func mixedStudentsKept() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let original = CDStudent(context: ctx)
        original.firstName = "Leora"
        let copy = CDStudent(context: ctx)
        copy.id = original.id
        copy.firstName = "Leora"
        #expect(CoreDataTestHelpers.save(ctx))

        let removed = withZones(shared: [original.objectID]) {
            DataCleanupService.deduplicateStudentsStrong(using: ctx)
        }
        #expect(removed == 0)
        #expect(original.managedObjectContext != nil && copy.managedObjectContext != nil)
    }

    @Test("Two copies on the same side of the boundary still fold into one")
    func sameSideStillFolds() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let first = CDStudent(context: ctx)
        let second = CDStudent(context: ctx)
        second.id = first.id
        #expect(CoreDataTestHelpers.save(ctx))

        let removed = withZones(shared: [first.objectID, second.objectID]) {
            DataCleanupService.deduplicateStudentsStrong(using: ctx)
        }
        #expect(removed == 1)
    }

    @Test("A day's attendance held in and out of the share keeps both records")
    func mixedAttendanceKept() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let studentID = UUID().uuidString
        let day = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 780_000_000))
        let original = CDAttendanceRecord(context: ctx)
        original.studentID = studentID
        original.date = day
        original.status = .present
        let copy = CDAttendanceRecord(context: ctx)
        copy.id = original.id
        copy.studentID = studentID
        copy.date = day
        copy.status = .present
        copy.modifiedAt = original.modifiedAt
        #expect(CoreDataTestHelpers.save(ctx))

        let removed = withZones(shared: [original.objectID]) {
            DataCleanupService.deduplicateAttendanceRecordsStrong(using: ctx)
        }
        #expect(removed == 0)
        #expect(original.managedObjectContext != nil && copy.managedObjectContext != nil)
    }

    @Test("Identical attendance copies outside the share fold to exactly one")
    func identicalCopiesFold() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let studentID = UUID().uuidString
        let day = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 780_000_000))
        let stamp = Date(timeIntervalSinceReferenceDate: 780_010_000)
        var records: [CDAttendanceRecord] = []
        let id = UUID()
        for _ in 0..<3 {
            let record = CDAttendanceRecord(context: ctx)
            record.id = id
            record.studentID = studentID
            record.date = day
            record.status = .absent
            record.modifiedAt = stamp
            records.append(record)
        }
        #expect(CoreDataTestHelpers.save(ctx))

        let removed = withZones(shared: []) {
            DataCleanupService.deduplicateAttendanceRecordsStrong(using: ctx)
        }
        #expect(removed == 2)
        // A deleted and saved object leaves its context.
        #expect(records.filter { $0.managedObjectContext != nil }.count == 1)
    }

    @Test("Without a container or an override, nothing is looked up and dedup is unchanged")
    func noContainerNoLookup() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let first = CDStudent(context: ctx)
        let second = CDStudent(context: ctx)
        second.id = first.id
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(!DedupShareBoundary.spansShare([first, second], container: nil))
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 1)
    }

    @Test("Only the share's types are ever looked up")
    func otherTypesIgnored() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let first = CDLesson(context: ctx)
        let second = CDLesson(context: ctx)
        #expect(CoreDataTestHelpers.save(ctx))
        let spans = withZones(shared: [first.objectID]) {
            DedupShareBoundary.spansShare([first, second], container: nil)
        }
        #expect(!spans)
    }
}
