import Foundation
import Testing
@testable import CosmicDaybook

/// The query embedder is created once and reused; a reused model must embed
/// a query exactly as a freshly created one does.
@Suite("Album semantic index: cached query model", .serialized)
struct AlbumSemanticQueryCacheTests {

    @Test("A cached query model gives the same vector as a fresh one", arguments: ["sentence", "contextual"])
    func cachedMatchesFresh(backend: String) async {
        if backend == "sentence" { await waitForSentenceModel() }
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

    /// The iOS 27 simulator loads the sentence model lazily: the first request
    /// in a process returns nil and one ~100 ms later returns the model (the
    /// Mac returns it at once). Waiting here makes a nil `fresh` mean "this
    /// runtime has no model" rather than "not loaded yet".
    private func waitForSentenceModel() async {
        var attempts = 0
        while !AlbumSemanticIndex.sentenceBackendAvailable(), attempts < 40 {
            attempts += 1
            try? await Task.sleep(for: .milliseconds(50))
        }
    }
}
