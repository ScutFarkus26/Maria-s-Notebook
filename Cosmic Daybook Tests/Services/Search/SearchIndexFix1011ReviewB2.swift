import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11 review (b), fix agent B2: a search during the launch
/// refresh shares that build instead of starting a second one (#2).
@Suite("Search index shares one build (10-11 review B2)")
@MainActor
struct SearchIndexFix1011ReviewB2 {

    private func makeOnDiskStack() throws -> (stack: CoreDataStack, directory: URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stack = try CoreDataStack(
            enableCloudKit: false,
            localStoreURL: directory.appendingPathComponent("unified.sqlite")
        )
        return (stack, directory)
    }

    @Test("A search during the launch refresh waits for it rather than building the index again")
    func searchDuringLaunchRefreshSharesTheBuild() async throws {
        let (stack, directory) = try makeOnDiskStack()
        CoreDataTestHelpers.seedNote(in: stack.viewContext, body: "Stamp game with Maya")
        try #require(CoreDataTestHelpers.save(stack.viewContext))

        let index = SearchIndexService(snapshotDirectory: directory.appendingPathComponent("snapshots"))
        index.adopt(stack.container)

        // The launch refresh, the Search sheet and a chat answer, all at once.
        async let launch: Void = index.refresh(container: stack.container)
        async let searchSheet: Void = index.ensureReady()
        async let chat: Void = index.ensureReady()
        _ = await (launch, searchSheet, chat)

        // Each wholesale build bumps the generation once.
        #expect(index.contentsGeneration == 1)
        #expect(index.isReady)
        #expect(index.search(query: "stamp").map(\.title) == ["Stamp game with Maya"])
    }

    @Test("Two refreshes at once build once; a later refresh builds again")
    func overlappingRefreshesShareOneBuild() async throws {
        let (stack, directory) = try makeOnDiskStack()
        CoreDataTestHelpers.seedNote(in: stack.viewContext, body: "Golden beads with Ari")
        try #require(CoreDataTestHelpers.save(stack.viewContext))

        let index = SearchIndexService(snapshotDirectory: directory.appendingPathComponent("snapshots"))
        async let first: Void = index.refresh(container: stack.container)
        async let second: Void = index.refresh(container: stack.container)
        _ = await (first, second)
        #expect(index.contentsGeneration == 1)

        // Once the shared build is over, a new refresh is a new build.
        await index.refresh(container: stack.container)
        #expect(index.contentsGeneration == 2)
    }
}
