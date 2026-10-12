import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12, #60: a work item's search result showed its status
// code ("keepPracticing"), in the app's search and in MCP `search_notebook`
// alike. It now reads as the app names the status, and the snapshot version
// moved on so a snapshot holding the old wording is rebuilt once.

@Suite("Search: work status wording (bug hunt 10-12)")
@MainActor
struct SearchSnippetFix1012LTests {

    @Test("A work item's search result names its status the way the app does")
    func workSnippetReadsAsTheAppNamesIt() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Golden bead addition")
        work.status = .keepPracticing
        #expect(CoreDataTestHelpers.save(context))

        let entry = try #require(SearchIndexService.entry(for: work))
        #expect(entry.result.snippet == "Keep Practicing")
    }

    @Test("A snapshot written before the wording changed is rebuilt, not reused")
    func oldSnapshotIsRebuilt() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let stack = try CoreDataStack(
            enableCloudKit: false, localStoreURL: directory.appendingPathComponent("unified.sqlite")
        )
        let snapshots = directory.appendingPathComponent("snapshots")
        let work = CoreDataTestHelpers.seedWorkModel(in: stack.viewContext, title: "Golden bead addition")
        work.status = .keepPracticing
        try #require(CoreDataTestHelpers.save(stack.viewContext))

        await SearchIndexService(snapshotDirectory: snapshots).refresh(container: stack.container)
        let identity = SearchIndexService.storeIdentity(of: stack.container)
        let url = SearchIndexSnapshotStore.url(in: snapshots, identity: identity)
        var old = try #require(SearchIndexSnapshotStore.load(from: url))

        // What the build before the fix wrote: version 1, the raw status code.
        old.version = 1
        old.entries = old.entries.map { entry in
            var raw = entry
            raw.result = SearchResult(
                id: entry.result.id, entityType: entry.result.entityType, title: entry.result.title,
                snippet: "keepPracticing", date: entry.result.date
            )
            return raw
        }
        SearchIndexSnapshotStore.write(old, to: url)

        let service = SearchIndexService(snapshotDirectory: snapshots)
        await service.refresh(container: stack.container)
        #expect(service.lastRefreshSource == .fullRebuild)
        #expect(service.search(query: "golden").map(\.snippet) == ["Keep Practicing"])
    }
}
