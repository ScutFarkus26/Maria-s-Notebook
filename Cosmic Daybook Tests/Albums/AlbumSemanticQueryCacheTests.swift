import Foundation
import Testing
@testable import CosmicDaybook

/// The query embedder is created once and reused; a reused model must embed
/// a query exactly as a freshly created one does.
@Suite("Album semantic index: cached query model", .serialized)
struct AlbumSemanticQueryCacheTests {

    @Test("A cached query model gives the same vector as a fresh one", arguments: ["sentence", "contextual"])
    func cachedMatchesFresh(backend: String) {
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
}
