import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// An index built when the store had no history yet (an empty notebook at
/// launch) has no token to replay from; the catch-up used to stop there for
/// the rest of the session (2026-10-05 hunt, #55).
@Suite("Search index catch-up with no indexed token")
@MainActor
struct SearchIndexCatchUpNoTokenTests {

    @Test("With no indexed token but history since, the catch-up rebuilds and finds the new note")
    func noIndexedTokenRefreshes() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stack = try CoreDataStack(
            enableCloudKit: false,
            localStoreURL: directory.appendingPathComponent("unified.sqlite")
        )
        let service = SearchIndexService(
            snapshotDirectory: directory.appendingPathComponent("snapshots"),
            catchUpDelay: .seconds(60)
        )
        await service.refresh(container: stack.container)
        // As a refresh over a store with no history leaves it.
        service.indexedHistoryToken = nil

        let note = CoreDataTestHelpers.seedNote(in: stack.viewContext, body: "Stamp game")
        note.id = UUID()
        try #require(CoreDataTestHelpers.save(stack.viewContext))
        await service.ensureReady()

        #expect(Set(service.search(query: "stamp").map(\.title)) == ["Stamp game"])
        #expect(service.indexedHistoryToken != nil)
    }
}
