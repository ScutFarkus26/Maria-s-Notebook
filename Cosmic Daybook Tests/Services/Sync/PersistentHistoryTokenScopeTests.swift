import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

// What a persistent-history token covers across the app's two stores. The
// history processor used to keep one token for both, the newest
// transaction's; these are the facts that made that cursor skip a store
// without a word, and the ones its per-store replacement relies on (see
// `PersistentHistoryProcessor+StoreHistory.swift`).

@Suite("Persistent history: what a token covers across two stores")
@MainActor
struct PersistentHistoryTokenScopeTests {

    @Test("A shared-store token returns nothing, and no error, past a newer private-store transaction")
    func tokenSkipsTheOtherStoreSilently() throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        try stores.write(.sharedStore)
        let sharedToken = try stores.newestToken(.sharedStore)
        try stores.write(.privateStore)

        #expect(try stores.history(after: sharedToken).isEmpty)
    }

    @Test("A token resumes after its transaction in its own store only")
    func tokenResumesItsOwnStore() throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        try stores.write(.privateStore)
        let privateToken = try stores.newestToken(.privateStore)
        try stores.write(.sharedStore)
        try stores.write(.privateStore)

        #expect(try stores.history(after: privateToken).map(\.storeID) == [stores.id(.privateStore)])
    }

    @Test("With no token, both stores' transactions come back interleaved by time")
    func noTokenInterleavesBothStores() throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        try stores.write(.privateStore)
        try stores.write(.sharedStore)
        try stores.write(.privateStore)

        let order = try stores.history(after: nil).map(\.storeID)
        #expect(order == [stores.id(.privateStore), stores.id(.sharedStore), stores.id(.privateStore)])
    }

    @Test("A token naming a store that is not loaded throws NSCocoaErrorDomain 134501")
    func tokenOfAnUnloadedStoreThrows() throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        let elsewhere = try TwoStoreHistoryFixture()
        defer { elsewhere.removeFiles() }
        try elsewhere.write(.privateStore)
        let foreignToken = try elsewhere.newestToken(.privateStore)

        let error = #expect(throws: NSError.self) {
            try stores.history(after: foreignToken)
        }
        #expect(error?.domain == NSCocoaErrorDomain)
        #expect(error?.code == 134_501)
    }

    @Test("A token decides which stores are read; affectedStores narrows only a fetch without one")
    func tokenOverridesAffectedStores() throws {
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        try stores.write(.sharedStore)
        let sharedToken = try stores.newestToken(.sharedStore)
        try stores.write(.privateStore)
        try stores.write(.sharedStore)

        // Scoped to the private store, the shared store's token still reads the
        // shared store, so a store's position must only ever be its own token.
        let scoped = try stores.history(after: sharedToken, scopedTo: [stores.privateStore])
        #expect(scoped.map(\.storeID) == [stores.id(.sharedStore)])
        let tokenless = try stores.history(after: nil, scopedTo: [stores.privateStore])
        #expect(tokenless.map(\.storeID) == [stores.id(.privateStore)])
    }

    @Test("The coordinator's token for both stores resumes each of them")
    func coordinatorTokenCoversBothStores() throws {
        // `BackupChangeTracker` records this token, so its gate sees both stores.
        let stores = try TwoStoreHistoryFixture()
        defer { stores.removeFiles() }
        try stores.write(.privateStore)
        try stores.write(.sharedStore)
        let both = try #require(
            stores.container.persistentStoreCoordinator.currentPersistentHistoryToken(
                fromStores: [stores.privateStore, stores.sharedStore]
            )
        )
        try stores.write(.sharedStore)
        try stores.write(.privateStore)

        let order = try stores.history(after: both).map(\.storeID)
        #expect(order == [stores.id(.sharedStore), stores.id(.privateStore)])
    }
}
