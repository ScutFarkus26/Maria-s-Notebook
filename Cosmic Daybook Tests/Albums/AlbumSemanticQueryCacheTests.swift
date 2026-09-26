import Foundation
import Testing
@testable import CosmicDaybook

/// The query embedder is created once and reused; a reused model must embed
/// a query exactly as a freshly created one does.
@Suite("Album semantic index: cached query model", .serialized)
struct AlbumSemanticQueryCacheTests {

    @Test("A cached sentence model gives the same vector as a fresh one")
    func cachedSentenceMatchesFresh() async throws {
        // Waits out the simulator's lazy sentence-model load (the first request
        // in a process returns nil). Every runtime the suite runs on has this
        // model, so a missing vector is a failure, not a pass.
        _ = await AlbumSemanticIndex.resolveTitleBackend()
        let fresh = try #require(AlbumSemanticIndex.sentenceEmbed([Self.text])?.first)
        expectCachedMatches(fresh, backend: "sentence")
    }

    /// The iOS 27 simulator can't load the contextual model ("Embedding model
    /// requires compilation"), so there this shows as skipped rather than
    /// passing with two empty results.
    @Test(
        "A cached contextual model gives the same vector as a fresh one",
        .enabled(
            if: AlbumSemanticIndex.loadedContextualEmbedding() != nil,
            "The contextual model can't load on this runtime"
        )
    )
    func cachedContextualMatchesFresh() throws {
        let fresh = try #require(AlbumSemanticIndex.contextualEmbed([Self.text])?.first)
        expectCachedMatches(fresh, backend: "contextual")
    }

    private static let text = "borrowing in subtraction"

    private func expectCachedMatches(_ fresh: [Float], backend: String) {
        AlbumSemanticIndex.releaseQueryEmbedders()
        let first = AlbumSemanticIndex.embedQuery(Self.text, backend: backend)
        let second = AlbumSemanticIndex.embedQuery(Self.text, backend: backend)
        #expect(first == fresh)
        #expect(second == fresh)
        // The model stays cached until released.
        #expect(AlbumSemanticIndex.hasCachedQueryEmbedder)
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
