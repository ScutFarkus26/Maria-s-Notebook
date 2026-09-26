import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the history processor's advance-on-empty step. When the author-filtered
/// read finds nothing remote, a second, unfiltered read moves the position past
/// what that filter leaves out (the app's own transactions and nil authors), but
/// only through their leading run: a transaction the filter would return
/// committed after the filtered read (a CloudKit import landing mid-pass), and
/// stepping over it would mean it is never processed. Run per store, on the
/// private store of the production two-store shape: on-disk SQLite, because
/// in-memory stores keep no history.
@Suite("Persistent history: advance on empty")
@MainActor
struct PersistentHistoryAdvanceTests {

    private let own = PersistentHistoryProcessor.transactionAuthor
    private let importAuthor = AdvanceFixture.importAuthor

    @Test("An import that committed between the two reads stops the position before it")
    func stopsBeforeAnImport() throws {
        let fixture = try AdvanceFixture()
        defer { fixture.cleanUp() }
        try fixture.write(as: own)
        try fixture.write(as: importAuthor)
        try fixture.write(as: own)

        let advance = try #require(fixture.advance())
        #expect(advance.passedOver == 1)
        // The next pass starts at the import, not after it.
        let next = try fixture.authors(after: advance.position)
        #expect(next == [importAuthor, own])
    }

    @Test("An import first in line keeps the position where it was")
    func importFirstKeepsPosition() throws {
        let fixture = try AdvanceFixture()
        defer { fixture.cleanUp() }
        try fixture.write(as: importAuthor)
        try fixture.write(as: own)

        #expect(fixture.advance() == nil)
    }

    @Test("A run of only the app's own transactions still advances to the end")
    func ownRunAdvancesToEnd() throws {
        let fixture = try AdvanceFixture()
        defer { fixture.cleanUp() }
        for _ in 0..<3 {
            try fixture.write(as: own)
        }

        let advance = try #require(fixture.advance())
        #expect(advance.passedOver == 3)
        let next = try fixture.authors(after: advance.position)
        #expect(next.isEmpty)
    }

    @Test("A nil author is stepped over like the app's own")
    func nilAuthorIsSteppedOver() throws {
        let fixture = try AdvanceFixture()
        defer { fixture.cleanUp() }
        try fixture.write(as: own)
        try fixture.write(as: nil)
        try fixture.write(as: own)
        try fixture.write(as: importAuthor)

        let advance = try #require(fixture.advance())
        #expect(advance.passedOver == 3)
        let next = try fixture.authors(after: advance.position)
        #expect(next == [importAuthor])
    }

    @Test("The store-level author filter leaves out a nil author as well as the app's own")
    func storeFilterLeavesOutNilAuthor() throws {
        let fixture = try AdvanceFixture()
        defer { fixture.cleanUp() }
        try fixture.write(as: nil)
        try fixture.write(as: importAuthor)
        try fixture.write(as: own)

        // The processor's first read. A nil author never reaches it as remote,
        // which is why the advance step may step over one.
        let remote = try fixture.authors(after: fixture.start, excluding: own)
        #expect(remote == [importAuthor])
    }
}

/// The private store of the production two-store shape
/// (`TwoStoreHistoryFixture`), read the way the processor reads it after its
/// first pass: from a position that is one of that store's transaction tokens.
@MainActor
private struct AdvanceFixture {
    /// The author CloudKit stamps on the transactions it imports.
    static let importAuthor = TwoStoreHistoryFixture.remoteAuthor

    /// What the advance step did: where it moved the position, and past how
    /// many transactions.
    struct Advance {
        let position: NSPersistentHistoryToken
        let passedOver: Int
    }

    /// Where the processor's position stands when a test starts: just after
    /// an import an earlier pass already read.
    let start: NSPersistentHistoryToken
    private let stores: TwoStoreHistoryFixture

    private var context: NSManagedObjectContext { stores.container.viewContext }

    init() throws {
        let stores = try TwoStoreHistoryFixture()
        try stores.write(.privateStore, as: Self.importAuthor)
        start = try stores.newestToken(.privateStore)
        self.stores = stores
    }

    /// One save, so one transaction, by `author`. Nil is a context that never
    /// set one.
    func write(as author: String?) throws {
        try stores.write(.privateStore, as: author)
    }

    /// The advance step run from `start`, as a pass whose filtered read came
    /// back empty runs it; nil when it leaves the position where it was.
    func advance() -> Advance? {
        let context = self.context
        let store = stores.privateStore
        let result = context.performAndWait {
            PersistentHistoryProcessor.advanceToken(
                of: store, after: start, author: PersistentHistoryProcessor.transactionAuthor, in: context
            )
        }
        switch result {
        case let .processed(newToken, remoteCount, totalCount, insertedEntityNames, changedEntityNames):
            // It only ever steps over what the filter leaves out: nothing to report.
            #expect(remoteCount == 0)
            #expect(insertedEntityNames.isEmpty && changedEntityNames.isEmpty)
            return Advance(position: newToken, passedOver: totalCount)
        case .noTransactions:
            return nil
        case .failed:
            Issue.record("The advance step reads with try? and has no failure path")
            return nil
        }
    }

    /// The authors of the transactions after `token`, oldest first: what the
    /// next pass reads. With `excluding`, filtered as the processor's first
    /// read filters.
    func authors(after token: NSPersistentHistoryToken, excluding author: String? = nil) throws -> [String?] {
        try Self.transactions(after: token, excluding: author, in: context).map(\.author)
    }

    func cleanUp() {
        stores.removeFiles()
    }

    private static func transactions(
        after token: NSPersistentHistoryToken?,
        excluding author: String?,
        in context: NSManagedObjectContext
    ) throws -> [NSPersistentHistoryTransaction] {
        // Inside the context's perform, as the processor reads: outside one,
        // `NSPersistentHistoryTransaction.fetchRequest` comes back nil.
        try context.performAndWait {
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            request.resultType = .transactionsOnly
            if let author {
                let filter = try #require(NSPersistentHistoryTransaction.fetchRequest)
                filter.predicate = NSPredicate(format: "author != %@", author)
                request.fetchRequest = filter
            }
            let result = try context.execute(request) as? NSPersistentHistoryResult
            return try #require(result?.result as? [NSPersistentHistoryTransaction])
        }
    }
}
