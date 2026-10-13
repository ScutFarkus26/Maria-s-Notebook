import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Schema 18: a student's ParentLocker match (`parentLockerID`) survives the
/// duplicate cleanup, so a child folded from two copies still sends by ID.
@Suite("Student dedup keeps the ParentLocker match")
@MainActor
struct DedupStudentParentLockerTests {

    private func twoCopies(_ firstID: String?, _ secondID: String?) throws -> (NSManagedObjectContext, [CDStudent]) {
        let ctx = try CoreDataTestHelpers.makeContext()
        let first = CDStudent(context: ctx)
        first.firstName = "Wren"
        first.lastName = "Halloway"
        first.parentLockerID = firstID
        let second = CDStudent(context: ctx)
        second.id = first.id
        second.firstName = "Wren"
        second.lastName = "Halloway"
        second.parentLockerID = secondID
        #expect(CoreDataTestHelpers.save(ctx))
        return (ctx, [first, second])
    }

    private func survivor(in context: NSManagedObjectContext) throws -> CDStudent {
        let left = context.safeFetch(CDFetchRequest(CDStudent.self)).filter { !$0.isDeleted }
        #expect(left.count == 1)
        return try #require(left.first)
    }

    @Test("The match on either copy is kept", arguments: [true, false])
    func matchOnOneCopy(onFirst: Bool) throws {
        let (ctx, _) = try twoCopies(onFirst ? "40001" : nil, onFirst ? nil : "40001")
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 1)
        #expect(try survivor(in: ctx).parentLockerID == "40001")
    }

    @Test("A blank match on the kept copy is filled from the other")
    func blankFilled() throws {
        let (ctx, _) = try twoCopies("", "40002")
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 1)
        let kept = try survivor(in: ctx)
        // Whichever copy was kept, it now holds the one real match.
        #expect(kept.parentLockerID == "40002")
    }

    @Test("The kept copy's own match is never replaced")
    func ownMatchKept() throws {
        let (ctx, copies) = try twoCopies("40001", "40002")
        let before = Dictionary(uniqueKeysWithValues: copies.map { ($0.objectID, $0.parentLockerID) })
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 1)
        let kept = try survivor(in: ctx)
        #expect(kept.parentLockerID == before[kept.objectID] ?? nil)
    }
}
