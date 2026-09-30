import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - Search index in-session catch-up
//
// After the launch refresh the index used to stay frozen until the next launch:
// on 2026-09-28 `search_notebook` still returned two students Delete Student had
// removed. These tests change the store *after* a refresh and check the same
// service instance sees it, through `ensureReady()` (what MCP and chat search
// call) and on its own after a store change, with no second refresh.

@Suite("Search index catch-up")
@MainActor
struct SearchIndexCatchUpTests {

    // MARK: - Fixtures

    private struct Fixture {
        let stack: CoreDataStack
        let directory: URL
        var context: NSManagedObjectContext { stack.viewContext }

        func service(catchUpDelay: Duration = .seconds(60)) -> SearchIndexService {
            SearchIndexService(
                snapshotDirectory: directory.appendingPathComponent("snapshots"),
                catchUpDelay: catchUpDelay
            )
        }
    }

    /// An on-disk store: history tracking, which the catch-up reads, needs SQLite.
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
        note.id = UUID()
        try #require(CoreDataTestHelpers.save(fixture.context))
        return note
    }

    private func titles(_ service: SearchIndexService, _ query: String) -> Set<String> {
        Set(service.search(query: query).map(\.title))
    }

    // MARK: - ensureReady catches up

    @Test("an insert after the refresh is found without a relaunch")
    func insertIsFound() async throws {
        let fixture = try makeFixture()
        try addNote("Golden beads", to: fixture)
        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)
        #expect(titles(service, "stamp").isEmpty)

        try addNote("Stamp game", to: fixture)
        await service.ensureReady()

        #expect(titles(service, "stamp") == ["Stamp game"])
        #expect(titles(service, "golden") == ["Golden beads"])
        #expect(service.lastRefreshSource == .fullRebuild, "caught up in place, not by another refresh")
        #expect(service.catchUpPasses == 1)
    }

    @Test("an update after the refresh re-indexes under the new text only")
    func updateIsReindexed() async throws {
        let fixture = try makeFixture()
        let note = try addNote("Pink tower", to: fixture)
        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)

        note.body = "Brown stair"
        try #require(CoreDataTestHelpers.save(fixture.context))
        await service.ensureReady()

        #expect(titles(service, "brown") == ["Brown stair"])
        #expect(titles(service, "pink").isEmpty, "the old text's tokens must not still match")
        #expect(service.index["pink"] == nil)
    }

    @Test("a deleted student no longer comes back from search")
    func deletedStudentIsDropped() async throws {
        let fixture = try makeFixture()
        let doomed = CoreDataTestHelpers.seedStudent(in: fixture.context, firstName: "Lil", lastName: "Dan")
        doomed.id = UUID()
        let kept = CoreDataTestHelpers.seedStudent(in: fixture.context, firstName: "Maya", lastName: "Dan")
        kept.id = UUID()
        try #require(CoreDataTestHelpers.save(fixture.context))
        let doomedID = try #require(doomed.id)
        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)
        #expect(service.search(query: "dan").count == 2)

        fixture.context.delete(doomed)
        try #require(CoreDataTestHelpers.save(fixture.context))
        await service.ensureReady()

        let ids = service.search(query: "dan").map(\.id)
        #expect(ids == [kept.id])
        #expect(service.resultsById[doomedID] == nil)
        #expect(service.search(query: "lil").isEmpty)
    }

    @Test("deleting one of two records sharing an id keeps the other findable")
    func duplicateSurvivorStaysIndexed() async throws {
        let fixture = try makeFixture()
        let shared = UUID()
        let original = CoreDataTestHelpers.seedNote(in: fixture.context, body: "Bead frame")
        original.id = shared
        let copy = CoreDataTestHelpers.seedNote(in: fixture.context, body: "Bead frame")
        copy.id = shared
        try #require(CoreDataTestHelpers.save(fixture.context))
        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)

        fixture.context.delete(copy)
        try #require(CoreDataTestHelpers.save(fixture.context))
        await service.ensureReady()

        #expect(service.search(query: "bead").map(\.id) == [shared])
    }

    // MARK: - Gates

    @Test("with nothing written since, ensureReady reads no history")
    func unchangedTokenSkipsReplay() async throws {
        let fixture = try makeFixture()
        try addNote("Golden beads", to: fixture)
        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)

        await service.ensureReady()
        await service.ensureReady()

        #expect(service.catchUpPasses == 0)
    }

    @Test("an unrelated save advances the token without touching the index")
    func unrelatedSaveLeavesIndexAlone() async throws {
        let fixture = try makeFixture()
        try addNote("Golden beads", to: fixture)
        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)
        let before = service.index

        let supply = CDSupply(context: fixture.context)
        supply.name = "Chalk"
        try #require(CoreDataTestHelpers.save(fixture.context))

        await service.ensureReady()
        await service.ensureReady()

        #expect(service.catchUpPasses == 1, "second call is gated on the advanced token")
        #expect(service.index == before)
    }

    @Test("a purge mid-session reloads, then later changes still catch up")
    func purgeThenCatchUp() async throws {
        let fixture = try makeFixture()
        try addNote("Golden beads", to: fixture)
        let service = fixture.service()
        await service.refresh(container: fixture.stack.container)

        service.purge()
        await service.ensureReady()
        try addNote("Stamp game", to: fixture)
        await service.ensureReady()

        #expect(titles(service, "stamp") == ["Stamp game"])
        #expect(titles(service, "golden") == ["Golden beads"])
    }

    // MARK: - Following the store

    @Test("a save is picked up on its own after the coalescing delay")
    func followsSavesWithoutBeingAsked() async throws {
        let fixture = try makeFixture()
        try addNote("Golden beads", to: fixture)
        let service = fixture.service(catchUpDelay: .milliseconds(50))
        await service.refresh(container: fixture.stack.container)

        try addNote("Stamp game", to: fixture)

        // Generous: the full parallel suite starves the main actor well past
        // 10 s (2026-09-30: failed at 23.7 s); a passing run returns early.
        let deadline = ContinuousClock.now + .seconds(60)
        while titles(service, "stamp").isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(25))
        }
        #expect(titles(service, "stamp") == ["Stamp game"])
    }
}
