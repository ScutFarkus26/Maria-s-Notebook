import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Schema 21: a child born after sunset (`bornAfterSunset`) stays so through
/// the duplicate cleanup, whichever copy carried the switch, so her Hebrew
/// birthday doesn't slip back a day.
@Suite("Student dedup keeps born after sunset")
@MainActor
struct DedupStudentBornAfterSunsetTests {

    private func twoCopies(_ first: Bool, _ second: Bool) throws -> NSManagedObjectContext {
        let ctx = try CoreDataTestHelpers.makeContext()
        let original = CDStudent(context: ctx)
        original.firstName = "Wren"
        original.lastName = "Halloway"
        original.bornAfterSunset = first
        let copy = CDStudent(context: ctx)
        copy.id = original.id
        copy.firstName = "Wren"
        copy.lastName = "Halloway"
        copy.bornAfterSunset = second
        #expect(CoreDataTestHelpers.save(ctx))
        return ctx
    }

    private func survivor(in context: NSManagedObjectContext) throws -> CDStudent {
        let left = context.safeFetch(CDFetchRequest(CDStudent.self)).filter { !$0.isDeleted }
        #expect(left.count == 1)
        return try #require(left.first)
    }

    @Test("The switch on either copy is kept", arguments: [true, false])
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
}
