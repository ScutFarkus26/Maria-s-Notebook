import Foundation
import Testing
@testable import CosmicDaybook

/// The query embedder is created once and reused; a reused model must embed
/// a query exactly as a freshly created one does.
@Suite("Album semantic index: cached query model", .serialized)
struct AlbumSemanticQueryCacheTests {

    @Test("A cached query model gives the same vector as a fresh one", arguments: ["sentence", "contextual"])
    func cachedMatchesFresh(backend: String) async {
        // Waits out the simulator's lazy sentence-model load, so a nil `fresh`
        // below means "this runtime has no model" rather than "not loaded yet".
        _ = await AlbumSemanticIndex.resolveTitleBackend()
        let text = "borrowing in subtraction"
        let fresh: [Float]? = backend == "sentence"
            ? AlbumSemanticIndex.sentenceEmbed([text])?.first
            : AlbumSemanticIndex.contextualEmbed([text])?.first
        AlbumSemanticIndex.releaseQueryEmbedders()
        let first = AlbumSemanticIndex.embedQuery(text, backend: backend)
        let second = AlbumSemanticIndex.embedQuery(text, backend: backend)
        #expect(first == fresh)
        #expect(second == fresh)
        // A model that exists on this runtime stays cached until released.
        #expect(AlbumSemanticIndex.hasCachedQueryEmbedder == (fresh != nil))
        AlbumSemanticIndex.releaseQueryEmbedders()
        #expect(AlbumSemanticIndex.hasCachedQueryEmbedder == false)
    }

    @Test("Five quiet minutes after a search the model goes; the next search reloads it and gets the same vector")
    func idleReleaseKeepsVectors() async throws {
        _ = await AlbumSemanticIndex.resolveTitleBackend()
        let text = "borrowing in subtraction"
        AlbumSemanticIndex.releaseQueryEmbedders()
        let before = try #require(AlbumSemanticIndex.embedQuery(text, backend: "sentence"))

        // The search armed the app's countdown, five minutes out.
        let appRelease = AlbumSemanticIndex.queryModelIdleRelease
        #expect(appRelease.interval == .seconds(300))
        #expect(appRelease.deadline != nil)
        #expect(AlbumSemanticIndex.hasCachedQueryEmbedder)

        // The same release on a clock the test moves.
        let clock = ManualTestClock()
        let release = IdleCountdown(interval: appRelease.interval, clock: clock) {
            AlbumSemanticIndex.releaseQueryEmbedders()
        }
        release.touch()
        clock.advance(by: .seconds(299))
        #expect(AlbumSemanticIndex.hasCachedQueryEmbedder)
        clock.advance(by: .seconds(1))
        #expect(await AlbumTestSupport.waitUntil { !AlbumSemanticIndex.hasCachedQueryEmbedder })

        let after = AlbumSemanticIndex.embedQuery(text, backend: "sentence")
        #expect(after == before)
        #expect(AlbumSemanticIndex.hasCachedQueryEmbedder)
        AlbumSemanticIndex.releaseQueryEmbedders()
    }
}
