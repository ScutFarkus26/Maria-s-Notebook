import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

// MARK: - Search index snapshot + history replay
//
// The launch-time refresh has three paths: reuse the snapshot untouched, patch
// it from persistent history, or do a full pass. These tests drive each path
// through a real on-disk store (history tracking needs SQLite) and check both
// the reported source and the search results, so a wrong path that happened
// to give right answers — or the reverse — would still fail.

@Suite("Search index snapshot")
@MainActor
struct SearchIndexSnapshotTests {

    // MARK: - Fixtures

    private struct Fixture {
        let stack: CoreDataStack
        let directory: URL
        var context: NSManagedObjectContext { stack.viewContext }

        func service(changeLimit: Int = 2_000) -> SearchIndexService {
            SearchIndexService(snapshotDirectory: directory.appendingPathComponent("snapshots"), incrementalChangeLimit: changeLimit)
        }
    }

    private func makeFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stack = try CoreDataStack(
            enableCloudKit: false,
            localStoreURL: directory.appendingPathComponent("unified.sqlite")
        )
        return Fixture(stack: stack, directory: directory)
    }

    @discardableResult
    private func addNote(_ body: String, to fixture: Fixture) throws -> CDNote {
        let note = CoreDataTestHelpers.seedNote(in: fixture.context, body: body)
        try #require(CoreDataTestHelpers.save(fixture.context))
        return note
    }

    private func titles(_ service: SearchIndexService, _ query: String) -> Set<String> {
        Set(service.search(query: query).map(\.title))
    }

    // MARK: - Tests

    @Test("first refresh is a full pass that writes a snapshot; the next is served from it")
    func fullPassThenSnapshot() async throws {
        let fixture = try makeFixture()
        try addNote("Golden beads introduction", to: fixture)

        let first = fixture.service()
        await first.refresh(container: fixture.stack.container)
        #expect(first.isReady)
        #expect(first.lastRefreshSource == .fullRebuild)
        #expect(titles(first, "golden") == ["Golden beads introduction"])

        let identity = SearchIndexService.storeIdentity(of: fixture.stack.container)
        let url = SearchIndexSnapshotStore.url(in: fixture.directory.appendingPathComponent("snapshots"), identity: identity)
        let snapshot = try #require(SearchIndexSnapshotStore.load(from: url))
        #expect(snapshot.storeIdentity == identity)
        #expect(snapshot.historyToken != nil)
        #expect(snapshot.entries.map(\.result.title) == ["Golden beads introduction"])

        let second = fixture.service()
        await second.refresh(container: fixture.stack.container)
        #expect(second.lastRefreshSource == .snapshot)
        #expect(titles(second, "golden") == ["Golden beads introduction"])
    }

    @Test("an insert since the snapshot is replayed from history")
    func insertIsReplayed() async throws {
        let fixture = try makeFixture()
        try addNote("Binomial cube", to: fixture)
        await fixture.service().refresh(container: fixture.stack.container)

        try addNote("Trinomial cube", to: fixture)

        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)
        #expect(service.lastRefreshSource == .incremental)
        #expect(titles(service, "cube") == ["Binomial cube", "Trinomial cube"])

        // The patched snapshot serves the launch after that unchanged.
        let next = fixture.service()
        await next.refresh(container: fixture.stack.container)
        #expect(next.lastRefreshSource == .snapshot)
        #expect(titles(next, "cube") == ["Binomial cube", "Trinomial cube"])
    }

    @Test("an update since the snapshot re-indexes the object under its new text")
    func updateIsReplayed() async throws {
        let fixture = try makeFixture()
        let note = try addNote("Pink tower", to: fixture)
        await fixture.service().refresh(container: fixture.stack.container)

        note.body = "Brown stair"
        try #require(CoreDataTestHelpers.save(fixture.context))

        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)
        #expect(service.lastRefreshSource == .incremental)
        #expect(titles(service, "brown") == ["Brown stair"])
        #expect(titles(service, "pink").isEmpty)
    }

    @Test("a delete since the snapshot removes the object")
    func deleteIsReplayed() async throws {
        let fixture = try makeFixture()
        let keep = try addNote("Sandpaper letters", to: fixture)
        let doomed = try addNote("Sandpaper numerals", to: fixture)
        await fixture.service().refresh(container: fixture.stack.container)

        fixture.context.delete(doomed)
        try #require(CoreDataTestHelpers.save(fixture.context))

        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)
        #expect(service.lastRefreshSource == .incremental)
        #expect(titles(service, "sandpaper") == [keep.body])
    }

    @Test("more searchable changes than the limit fall back to a full pass")
    func changeLimitFallsBack() async throws {
        let fixture = try makeFixture()
        try addNote("Bead chain 1", to: fixture)
        await fixture.service(changeLimit: 1).refresh(container: fixture.stack.container)

        try addNote("Bead chain 2", to: fixture)
        try addNote("Bead chain 3", to: fixture)

        let service = fixture.service(changeLimit: 1)
        await service.refresh(container: fixture.stack.container)
        #expect(service.lastRefreshSource == .fullRebuild)
        #expect(titles(service, "chain").count == 3)
    }

    @Test("a snapshot from another store is ignored")
    func foreignSnapshotIsIgnored() async throws {
        let fixture = try makeFixture()
        try addNote("Moveable alphabet", to: fixture)
        let identity = SearchIndexService.storeIdentity(of: fixture.stack.container)
        let directory = fixture.directory.appendingPathComponent("snapshots")

        // Plant a snapshot at this store's URL that claims a different identity.
        let foreign = SearchIndexSnapshot(
            storeIdentity: ["not-this-store"],
            historyToken: Data([1, 2, 3]),
            entries: [.init(
                result: SearchResult(id: UUID(), entityType: .note, title: "Ghost", snippet: ""),
                text: "ghost", objectURI: "x-coredata://ghost"
            )]
        )
        SearchIndexSnapshotStore.write(foreign, to: SearchIndexSnapshotStore.url(in: directory, identity: identity))

        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)
        #expect(service.lastRefreshSource == .fullRebuild)
        #expect(titles(service, "ghost").isEmpty)
        #expect(titles(service, "moveable") == ["Moveable alphabet"])
    }

    @Test("an unreadable snapshot file falls back to a full pass")
    func corruptSnapshotFallsBack() async throws {
        let fixture = try makeFixture()
        try addNote("Metal insets", to: fixture)
        let identity = SearchIndexService.storeIdentity(of: fixture.stack.container)
        let directory = fixture.directory.appendingPathComponent("snapshots")
        let url = SearchIndexSnapshotStore.url(in: directory, identity: identity)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)

        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)
        #expect(service.lastRefreshSource == .fullRebuild)
        #expect(titles(service, "metal") == ["Metal insets"])
        #expect(SearchIndexSnapshotStore.load(from: url) != nil, "the full pass replaces the bad file")
    }

    @Test("without a snapshot directory the index is memory-only")
    func noDirectoryMeansNoFile() async throws {
        let fixture = try makeFixture()
        try addNote("Constructive triangles", to: fixture)
        let service = SearchIndexService(snapshotDirectory: nil)
        await service.refresh(container: fixture.stack.container)
        #expect(service.lastRefreshSource == .fullRebuild)
        #expect(titles(service, "triangles") == ["Constructive triangles"])
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("snapshots").path))
    }

    @Test("purge then ensureReady reloads from the snapshot")
    func purgeReloadsFromSnapshot() async throws {
        let fixture = try makeFixture()
        try addNote("Checkerboard", to: fixture)
        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)

        service.purge()
        #expect(!service.isReady)
        await service.ensureReady()
        #expect(service.isReady)
        #expect(service.lastRefreshSource == .snapshot)
        #expect(titles(service, "checker") == ["Checkerboard"])
    }
}
