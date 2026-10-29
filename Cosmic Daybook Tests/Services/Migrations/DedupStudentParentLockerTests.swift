import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Schema 18: a student's ParentLocker match (`parentLockerID`) survives the
/// duplicate cleanup, so a child folded from two copies still sends by ID;
/// and a match cleared on the copy changed last stays cleared (bug hunt
/// 2026-10-29: an older copy brought it back).
@Suite("Student dedup keeps the ParentLocker match")
@MainActor
struct DedupStudentParentLockerTests {

    private static let changed = Date(timeIntervalSince1970: 1_790_000_000)

    /// Two copies of one child. Changed at the same moment unless
    /// `secondChangedLater`, which makes the second copy the newer.
    private func twoCopies(
        _ firstID: String?, _ secondID: String?, secondChangedLater: Bool = false
    ) throws -> (NSManagedObjectContext, [CDStudent]) {
        let ctx = try CoreDataTestHelpers.makeContext()
        let first = CDStudent(context: ctx)
        first.firstName = "Wren"
        first.lastName = "Halloway"
        first.parentLockerID = firstID
        first.modifiedAt = Self.changed
        let second = CDStudent(context: ctx)
        second.id = first.id
        second.firstName = "Wren"
        second.lastName = "Halloway"
        second.parentLockerID = secondID
        second.modifiedAt = Self.changed.addingTimeInterval(secondChangedLater ? 60 : 0)
        #expect(CoreDataTestHelpers.save(ctx))
        return (ctx, [first, second])
    }

    private func survivor(in context: NSManagedObjectContext) throws -> CDStudent {
        let left = context.safeFetch(CDFetchRequest(CDStudent.self)).filter { !$0.isDeleted }
        #expect(left.count == 1)
        return try #require(left.first)
    }

    @Test("Copies changed together: the match on either is kept", arguments: [true, false])
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

    @Test("Copies changed together: the kept copy's own match is never replaced")
    func ownMatchKept() throws {
        let (ctx, copies) = try twoCopies("40001", "40002")
        let before = Dictionary(uniqueKeysWithValues: copies.map { ($0.objectID, $0.parentLockerID) })
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 1)
        let kept = try survivor(in: ctx)
        #expect(kept.parentLockerID == before[kept.objectID] ?? nil)
    }

    @Test("A match cleared on the copy changed last stays cleared, whichever copy is kept")
    func clearedOnTheNewerCopyStaysCleared() throws {
        let (ctx, _) = try twoCopies("40001", nil, secondChangedLater: true)
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 1)
        let kept = try survivor(in: ctx)
        #expect(kept.parentLockerID == nil, "the older copy's match doesn't come back")
        #expect(kept.modifiedAt == Self.changed.addingTimeInterval(60))
    }

    @Test("A match made on the copy changed last wins over the older copy's")
    func newerMatchWins() throws {
        let (ctx, _) = try twoCopies("40001", "40002", secondChangedLater: true)
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 1)
        #expect(try survivor(in: ctx).parentLockerID == "40002")
    }

    @Test("Of three copies, the one changed last decides")
    func threeCopies() throws {
        let (ctx, copies) = try twoCopies(nil, "40001", secondChangedLater: true)
        let third = CDStudent(context: ctx)
        third.id = copies[0].id
        third.firstName = "Wren"
        third.lastName = "Halloway"
        third.parentLockerID = "40009"
        third.modifiedAt = Self.changed.addingTimeInterval(30)
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(DataCleanupService.deduplicateStudentsStrong(using: ctx) == 2)
        #expect(try survivor(in: ctx).parentLockerID == "40001")
    }

    @Test("Matching a child stamps her as changed, so the cleanup can tell which copy is newer")
    func matchingStampsTheChange() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let wren = CDStudent(context: ctx)
        wren.firstName = "Wren"
        wren.lastName = "Halloway"
        wren.modifiedAt = Self.changed
        #expect(CoreDataTestHelpers.save(ctx))
        let id = try #require(wren.id)

        #expect(ParentLockerCoreDataStore(context: ctx).writeMatches([id: "40001"]))
        let matchedAt = try #require(wren.modifiedAt)
        #expect(matchedAt > Self.changed)
        #expect(ParentLockerCoreDataStore(context: ctx).writeMatches([id: nil]))
        #expect(try #require(wren.modifiedAt) >= matchedAt)
        #expect(wren.parentLockerID == nil)
    }
}
