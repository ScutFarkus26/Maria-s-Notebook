import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

// The history processor keeps one position per store, because a history
// token covers only its own transaction's store (see
// `PersistentHistoryTokenScopeTests`). These pin that cursor and what it
// keeps from the single-token one: the author filter, advance-on-empty, and
// fail-open on an unreadable store. The processor-level tests write only the
// app's own transactions, so no pass here asks the shared dedup coordinator
// for anything or posts a process-wide notification.

@Suite("Persistent history: one cursor per store")
@MainActor
struct PersistentHistoryStoreCursorTests {

    private typealias Side = TwoStoreHistoryFixture.Side
    private static let ownAuthor = TwoStoreHistoryFixture.ownAuthor

    nonisolated private struct SuiteUnavailable: Error {}

    /// The defaults a processor under test owns. Built here rather than with
    /// `#require`, whose result belongs to the main actor and so could not be
    /// handed to the processor actor.
    nonisolated private static func processorDefaults(suite: String) throws -> UserDefaults {
        guard let defaults = UserDefaults(suiteName: suite) else { throw SuiteUnavailable() }
        return defaults
    }

    // MARK: - One pass

    @Test(
        "A pass whose newest transaction is in one store does not stop the next pass reading the other",
        arguments: TwoStoreHistoryFixture.Side.allCases
    )
    func nextPassReadsTheOtherStore(newest: TwoStoreHistoryFixture.Side) async throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        let other = newest.other
        try stores.write(other)
        try stores.write(newest)

        // A first pass reads both stores from their beginning.
        let first = await stores.pass(after: [:])
        let bothEntities: Set<String> = [Side.privateStore.entityName, Side.sharedStore.entityName]
        #expect(first.outcome == .processed(
            remoteCount: 2, totalCount: 2, insertedEntityNames: bothEntities, changedEntityNames: bothEntities
        ))
        #expect(Set(first.positions.keys) == [stores.id(.privateStore), stores.id(.sharedStore)])

        try stores.write(other)

        // The single cursor the processor used to keep, the newest
        // transaction's token, misses the change and says nothing.
        let oldCursor = try stores.newestToken(newest)
        #expect(try stores.history(after: oldCursor).isEmpty)

        // One position per store sees it, and leaves the quiet store's alone.
        let second = await stores.pass(after: first.positions)
        let otherEntity: Set<String> = [other.entityName]
        #expect(second.outcome == .processed(
            remoteCount: 1, totalCount: 1, insertedEntityNames: otherEntity, changedEntityNames: otherEntity
        ))
        #expect(second.positions[stores.id(newest)] == first.positions[stores.id(newest)])
        let otherNewest = try stores.newestToken(other)
        #expect(second.positions[stores.id(other)] == otherNewest)
    }

    @Test("Own transactions are left out of the report but still move each store's position")
    func ownTransactionsMovePositionsUnreported() async throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        try stores.write(.privateStore, as: Self.ownAuthor)
        try stores.write(.sharedStore, as: Self.ownAuthor)

        let first = await stores.pass(after: [:])
        #expect(first.outcome == .processed(
            remoteCount: 0, totalCount: 2, insertedEntityNames: [], changedEntityNames: []
        ))
        let privateNewest = try stores.newestToken(.privateStore)
        let sharedNewest = try stores.newestToken(.sharedStore)
        #expect(first.positions == [stores.id(.privateStore): privateNewest, stores.id(.sharedStore): sharedNewest])

        // Nothing new anywhere: no position moves, so nothing is saved or rescanned.
        let second = await stores.pass(after: first.positions)
        #expect(second.outcome == .noTransactions)
        #expect(second.positions == first.positions)
    }

    @Test("Only other authors' transactions are reported")
    func onlyRemoteTransactionsAreReported() async throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        try stores.write(.privateStore, as: Self.ownAuthor)
        try stores.write(.privateStore)
        try stores.write(.sharedStore, as: Self.ownAuthor)

        let result = await stores.pass(after: [:])
        let note: Set<String> = [Side.privateStore.entityName]
        #expect(result.outcome == .processed(
            remoteCount: 1, totalCount: 2, insertedEntityNames: note, changedEntityNames: note
        ))
    }

    @Test("A store whose history cannot be read fails the pass open and restarts alone")
    func unreadableStoreRestartsAlone() async throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        let elsewhere = try TwoStoreHistoryFixture()
        defer { elsewhere.removeFiles() }
        try elsewhere.write(.privateStore)
        try stores.write(.privateStore)
        try stores.write(.sharedStore)
        let settled = await stores.pass(after: [:])
        try stores.write(.sharedStore)

        // A position that no longer reads: a token from another store file
        // throws 134501, and history purged past a position throws too.
        var positions = settled.positions
        positions[stores.id(.privateStore)] = try elsewhere.newestToken(.privateStore)
        let failed = await stores.pass(after: positions)
        #expect(failed.outcome == .failed)
        #expect(failed.positions[stores.id(.privateStore)] == nil)
        let sharedNewest = try stores.newestToken(.sharedStore)
        #expect(failed.positions[stores.id(.sharedStore)] == sharedNewest)

        // The next pass reads the private store from its beginning; the shared store has nothing new.
        let recovered = await stores.pass(after: failed.positions)
        let note: Set<String> = [Side.privateStore.entityName]
        #expect(recovered.outcome == .processed(
            remoteCount: 1, totalCount: 1, insertedEntityNames: note, changedEntityNames: note
        ))
    }

    @Test("Positions of stores that are no longer loaded are dropped")
    func unloadedStorePositionsAreDropped() async throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        try stores.write(.privateStore, as: Self.ownAuthor)
        try stores.write(.sharedStore, as: Self.ownAuthor)
        let settled = await stores.pass(after: [:])

        // Reset Local Cache replaces both store files, and new files get new identifiers.
        var positions = settled.positions
        positions[UUID().uuidString] = settled.positions[stores.id(.privateStore)]
        let next = await stores.pass(after: positions)
        #expect(next.outcome == .noTransactions)
        #expect(next.positions == settled.positions)
    }

    // MARK: - Across launches

    @Test("The processor saves one position per store, keeps them across a relaunch, and drops the old token")
    func positionsSurviveARelaunch() async throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        let suite = "PersistentHistoryStoreCursorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data([0x01]), forKey: UserDefaultsKeys.persistentHistoryLastToken)

        let processor = PersistentHistoryProcessor(
            container: stores.container, defaults: try Self.processorDefaults(suite: suite)
        )
        #expect(defaults.object(forKey: UserDefaultsKeys.persistentHistoryLastToken) == nil)

        try stores.write(.privateStore, as: Self.ownAuthor)
        try stores.write(.sharedStore, as: Self.ownAuthor)
        await processor.processRemoteChanges()
        let privateNewest = try stores.newestToken(.privateStore)
        let sharedNewest = try stores.newestToken(.sharedStore)
        let saved = PersistentHistoryProcessor.loadPositions(from: defaults)
        #expect(saved == [stores.id(.privateStore): privateNewest, stores.id(.sharedStore): sharedNewest])

        // A relaunch loads the saved positions (dropping one for a store that
        // is gone), then moves only the store that changed.
        var withGoneStore = saved
        withGoneStore[UUID().uuidString] = privateNewest
        PersistentHistoryProcessor.savePositions(withGoneStore, to: defaults)
        let relaunched = PersistentHistoryProcessor(
            container: stores.container, defaults: try Self.processorDefaults(suite: suite)
        )
        try stores.write(.sharedStore, as: Self.ownAuthor)
        await relaunched.processRemoteChanges()
        let sharedNewer = try stores.newestToken(.sharedStore)
        let resumed = PersistentHistoryProcessor.loadPositions(from: defaults)
        #expect(resumed == [stores.id(.privateStore): privateNewest, stores.id(.sharedStore): sharedNewer])
    }

    @Test("Saved positions round-trip; an unreadable entry is skipped; no positions removes the key")
    func positionsRoundTripThroughDefaults() throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        let suite = "PersistentHistoryStoreCursorTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try stores.write(.privateStore)
        let token = try stores.newestToken(.privateStore)

        PersistentHistoryProcessor.savePositions([stores.id(.privateStore): token], to: defaults)
        #expect(PersistentHistoryProcessor.loadPositions(from: defaults) == [stores.id(.privateStore): token])

        let key = UserDefaultsKeys.persistentHistoryStoreTokens
        let unreadable: [String: Any] = ["garbled": Data([0x00]), "not-data": "text"]
        defaults.set(unreadable, forKey: key)
        #expect(PersistentHistoryProcessor.loadPositions(from: defaults).isEmpty)

        PersistentHistoryProcessor.savePositions([:], to: defaults)
        #expect(defaults.object(forKey: key) == nil)
    }
}
