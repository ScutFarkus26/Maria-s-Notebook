import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Schema 21: a child born after sunset (`bornAfterSunset`) stays so through
/// the duplicate cleanup, whichever copy carried the switch, so her Hebrew
/// birthday doesn't slip back a day; and a switch turned off on the copy
/// changed last stays off (bug hunt 2026-10-29).
@Suite("Student dedup keeps born after sunset")
@MainActor
struct DedupStudentBornAfterSunsetTests {

    private static let changed = Date(timeIntervalSince1970: 1_790_000_000)

    /// Two copies of one child, changed at the same moment unless
    /// `secondChangedLater`, which makes the second copy the newer.
    private func twoCopies(_ first: Bool, _ second: Bool, secondChangedLater: Bool = false) throws
        -> NSManagedObjectContext {
        let ctx = try CoreDataTestHelpers.makeContext()
        let original = CDStudent(context: ctx)
        original.firstName = "Wren"
        original.lastName = "Halloway"
        original.bornAfterSunset = first
        original.modifiedAt = Self.changed
        let copy = CDStudent(context: ctx)
        copy.id = original.id
        copy.firstName = "Wren"
        copy.lastName = "Halloway"
        copy.bornAfterSunset = second
        copy.modifiedAt = Self.changed.addingTimeInterval(secondChangedLater ? 60 : 0)
        #expect(CoreDataTestHelpers.save(ctx))
        return ctx
    }

    private func survivor(in context: NSManagedObjectContext) throws -> CDStudent {
        let left = context.safeFetch(CDFetchRequest(CDStudent.self)).filter { !$0.isDeleted }
        #expect(left.count == 1)
        return try #require(left.first)
    }

    @Test("Copies changed together: the switch on either is kept", arguments: [true, false])
    func switchOnOneCopy(onFirst: Bool) throws {
        let ctx = try twoCopies(onFirst, !onFirst)
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 1)
        #expect(try survivor(in: ctx).bornAfterSunset)
    }

    @Test("Two copies born by day stay by day")
    func neitherCopy() throws {
        let ctx = try twoCopies(false, false)
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 1)
        #expect(try !survivor(in: ctx).bornAfterSunset)
    }

    @Test("The copy changed last decides, switched on or off", arguments: [true, false])
    func newerCopyDecides(newerSaysAfterSunset: Bool) throws {
        let ctx = try twoCopies(!newerSaysAfterSunset, newerSaysAfterSunset, secondChangedLater: true)
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 1)
        #expect(try survivor(in: ctx).bornAfterSunset == newerSaysAfterSunset)
    }
}
