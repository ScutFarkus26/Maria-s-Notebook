import Foundation
import NaturalLanguage
import PDFKit
@testable import CosmicDaybook

/// The album index code as it was before Energy Fifty #42 (binary vector cache,
/// lazy fold, per-page and per-text autorelease pools), kept verbatim so the
/// equivalence tests can hold the new code against it. Only the wrapping
/// (static functions taking the index's dictionaries) is new.
nonisolated enum LegacyAlbumIndex {

    // MARK: AlbumSemanticIndex: the JSON vector cache

    nonisolated struct CachedVectors: Codable {
        let modified: Date
        let titleBackend: String
        let titles: [[Float]]
        let bodies: [[Float]]?
    }

    /// Writes the cache as `loadOrBuildVectors` did after embedding an album.
    static func writeVectors(_ cached: CachedVectors, albumID: String, in cacheDir: URL) throws {
        let cacheURL = cacheDir.appendingPathComponent(albumID + ".vectors2.json")
        let data = try JSONEncoder().encode(cached)
        try data.write(to: cacheURL)
    }

    /// The cache-hit half of `loadOrBuildVectors`: the vectors an old build
    /// ranked with.
    static func cachedVectors(for item: AlbumSemanticIndex.BuildItem, backend: String,
                              cacheDir: URL?) -> AlbumSemanticIndex.VectorSet? {
        let (modified, titles) = (item.modified, item.titles)
        let cacheURL = cacheDir?.appendingPathComponent(item.id + ".vectors2.json")
        if let cacheURL,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(CachedVectors.self, from: data),
           abs(cached.modified.timeIntervalSince(modified)) < 1,
           cached.titles.count == titles.count,
           cached.titleBackend == backend {
            return AlbumSemanticIndex.VectorSet(titles: cached.titles, titleBackend: cached.titleBackend,
                                                bodies: cached.bodies)
        }
        return nil
    }

    // MARK: AlbumSemanticIndex: ranking

    static func similarities(titleVectors: [String: [[Float]]], query: [Float], albumID: String) -> [Float]? {
        titleVectors[albumID]?.map { dot($0, query) }
    }

    static func normalizedSimilarities(titleVectors: [String: [[Float]]], matchThreshold: Float,
                                       query: [Float], albumID: String) -> [Float]? {
        let threshold = matchThreshold
        return similarities(titleVectors: titleVectors, query: query, albumID: albumID)?
            .map { max(0, ($0 - threshold) / (1 - threshold)) }
    }

    static func topMatches(titleVectors: [String: [[Float]]], query: [Float],
                           limit: Int) -> [AlbumSemanticIndex.Match] {
        var out: [AlbumSemanticIndex.Match] = []
        for (albumID, albumVectors) in titleVectors {
            for (i, vector) in albumVectors.enumerated() {
                out.append(AlbumSemanticIndex.Match(albumID: albumID, lessonIndex: i,
                                                    score: dot(vector, query)))
            }
        }
        return Array(out.sorted { $0.score > $1.score }.prefix(limit))
    }

    static func related(titleVectors: [String: [[Float]]], bodyVectors: [String: [[Float]]],
                        albumID: String, lessonIndex: Int, limit: Int) -> [AlbumSemanticIndex.Match] {
        let source = bodyVectors.isEmpty ? titleVectors : bodyVectors
        guard let albumVectors = source[albumID],
              albumVectors.indices.contains(lessonIndex) else { return [] }
        let query = albumVectors[lessonIndex]
        var out: [AlbumSemanticIndex.Match] = []
        for (candidateAlbum, candidateVectors) in source {
            for (i, vector) in candidateVectors.enumerated() {
                if candidateAlbum == albumID && abs(i - lessonIndex) <= 1 { continue }
                out.append(AlbumSemanticIndex.Match(albumID: candidateAlbum, lessonIndex: i,
                                                    score: dot(vector, query)))
            }
        }
        return Array(out.sorted { $0.score > $1.score }.prefix(limit))
    }

    static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var total: Float = 0
        for i in a.indices { total += a[i] * b[i] }
        return total
    }

    // MARK: AlbumSemanticIndex: sentence embedding, before the per-text pools

    static func sentenceEmbed(_ texts: [String], with embedding: NLEmbedding) -> [[Float]] {
        texts.map { text in
            let clipped = String(text.prefix(500))
            guard let vector = embedding.vector(for: clipped) else {
                return [Float](repeating: 0, count: embedding.dimension)
            }
            return AlbumSemanticIndex.normalize(vector.map(Float.init))
        }
    }

    // MARK: AlbumLibrary: the page-text index, before the lazy fold and per-page pools

    nonisolated struct CachedIndex: Codable {
        let modified: Date
        let pageTexts: [String]
    }

    static func loadOrBuildIndex(url: URL, modified: Date, cacheDir: URL?)
        -> (texts: [String], folded: [String]) {
        let cacheURL = cacheDir?.appendingPathComponent(url.lastPathComponent + ".index.json")
        if let cacheURL,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(CachedIndex.self, from: data),
           abs(cached.modified.timeIntervalSince(modified)) < 1 {
            return (cached.pageTexts, cached.pageTexts.map { $0.folded() })
        }
        var texts: [String] = []
        if let doc = PDFDocument(url: url) {
            for i in 0..<doc.pageCount {
                let raw = doc.page(at: i)?.string ?? ""
                texts.append(AlbumLibrary.normalize(raw))
            }
        }
        if let cacheURL,
           let data = try? JSONEncoder().encode(CachedIndex(modified: modified, pageTexts: texts)) {
            try? data.write(to: cacheURL)
        }
        return (texts, texts.map { $0.folded() })
    }
}
