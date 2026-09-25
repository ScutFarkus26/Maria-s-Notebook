import Foundation
import Testing
@testable import CosmicDaybook

/// Every album in a launch is embedded with the one title model chosen for the
/// process, so query vectors (always from that model) can match all of them.
@Suite("Album semantic index: one title model per launch", .serialized)
struct AlbumSemanticBackendTests {

    private let album = AlbumSemanticIndex.BuildItem(
        id: "Math", modified: .distantPast,
        titles: ["Simple Operations: Subtraction", "Stamp Game Division"],
        bodies: ["Borrowing with the stamp game.", "Sharing out the stamps among the skittles."])

    @Test("The title model is decided once and matches what the runtime has")
    func resolvesOnce() async {
        let first = await AlbumSemanticIndex.resolveTitleBackend()
        let second = await AlbumSemanticIndex.resolveTitleBackend()
        #expect(first == second)
        #expect((first == "sentence") == AlbumSemanticIndex.sentenceBackendAvailable())
    }

    @Test("An album is built with the chosen model, never the other one")
    func buildsWithChosenModel() async throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // The sentence model is available here, so re-deciding per album would pick it.
        try #require(await AlbumSemanticIndex.resolveTitleBackend() == "sentence")
        let result = AlbumSemanticIndex.loadOrBuildVectors(
            for: album, backend: "contextual", cacheDir: dir)
        if AlbumSemanticIndex.loadedContextualEmbedding() == nil {
            // The iOS 27 simulator can't load the contextual model ("requires
            // compilation"): the album is left out, not built with sentence vectors.
            #expect(result == nil)
        } else {
            #expect(result?.titleBackend == "contextual")
            #expect(result?.titles.count == album.titles.count)
        }
    }

    @Test("A cache from the chosen model is reused; one from the other model is never served")
    func cacheFollowsChosenModel() async throws {
        let dir = try makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        try #require(await AlbumSemanticIndex.resolveTitleBackend() == "sentence")
        let file = dir.appendingPathComponent("Math.vectors2.json")
        func build(_ backend: String) -> AlbumSemanticIndex.VectorSet? {
            AlbumSemanticIndex.loadOrBuildVectors(for: album, backend: backend, cacheDir: dir)
        }
        func written() throws -> Date? {
            try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }

        let built = try #require(build("sentence"))
        let sentenceWrite = try written()
        let reused = try #require(build("sentence"))
        #expect(reused.titleBackend == "sentence")
        #expect(reused.titles == built.titles)
        #expect(try written() == sentenceWrite)

        // Asked for the other model, the sentence cache is not handed back:
        // the album is rebuilt with it, or left out where it can't load.
        let other = build("contextual")
        #expect(other?.titleBackend != "sentence")
        if other != nil { #expect(try written() != sentenceWrite) }
    }

    private func makeCacheDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlbumSemanticBackendTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
