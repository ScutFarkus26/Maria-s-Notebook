import Foundation
import NaturalLanguage

/// On-device embeddings for every lesson, so search can match meaning
/// ("borrowing") to lessons that never use the word ("Simple Operations:
/// Subtraction"). Two vector sets, chosen by measurement on the real albums:
///
/// - Title vectors (static sentence embedding of the lesson title) match
///   short queries well — short-to-short comparison keeps scores
///   discriminative.
/// - Body vectors (contextual embedding of title + lesson text) capture
///   what a lesson is about, and drive lesson-to-lesson "Related Lessons".
///
/// Everything runs locally; vectors are cached per album.
///
/// Related to but separate from `Stories/StoryLessonMatcher`, which matches
/// stories to lessons with averaged word vectors. This index works over album
/// lesson titles and bodies; consolidating the two is a possible follow-up.
@Observable @MainActor
final class AlbumSemanticIndex {
    enum Status: Equatable { case idle, building, ready, unavailable }

    var status: Status = .idle
    /// albumID → one vector per entry of Album.lessons.
    private var titleVectors: [String: [[Float]]] = [:]
    private var bodyVectors: [String: [[Float]]] = [:]
    private var titleBackend = ""

    /// Below this cosine score a query match is noise, not meaning.
    var matchThreshold: Float { titleBackend == "sentence" ? 0.55 : 0.88 }

    nonisolated struct Match: Sendable, Identifiable {
        var id: String { "\(albumID)|\(lessonIndex)" }
        let albumID: String
        let lessonIndex: Int
        let score: Float
    }

    // MARK: Building

    /// Drops the embedding vectors under critical memory pressure. They are the
    /// index's whole footprint — one vector per lesson title and body, for every
    /// album — and `loadOrBuildVectors` reads them back from the on-disk cache,
    /// so a purge costs a reload rather than a re-embedding.
    func purge() {
        titleVectors.removeAll()
        bodyVectors.removeAll()
        status = .idle
    }

    func build(items: [(id: String, modified: Date, titles: [String], bodies: [String])]) async {
        guard status != .building else { return }
        status = .building
        let cacheDir = Self.cacheDirectory()
        var anySucceeded = false
        for item in items {
            let result = await Task.detached(priority: .utility) {
                Self.loadOrBuildVectors(albumID: item.id, modified: item.modified,
                                        titles: item.titles, bodies: item.bodies,
                                        cacheDir: cacheDir)
            }.value
            if let result {
                titleVectors[item.id] = result.titles
                titleBackend = result.titleBackend
                if let bodies = result.bodies {
                    bodyVectors[item.id] = bodies
                }
                anySucceeded = true
            }
        }
        status = anySucceeded ? .ready : .unavailable
    }

    // MARK: Queries

    func queryVector(for text: String) async -> [Float]? {
        guard status == .ready else { return nil }
        let backend = titleBackend
        return await Task.detached(priority: .userInitiated) {
            Self.embedQuery(text, backend: backend)
        }.value
    }

    /// Per-lesson similarity for one album, aligned with Album.lessons.
    func similarities(query: [Float], albumID: String) -> [Float]? {
        titleVectors[albumID]?.map { Self.dot($0, query) }
    }

    /// Similarities rescaled so 0 means "at or below the noise floor" and
    /// values approach 1 only for strong matches — safe to use as a ranking
    /// boost regardless of which embedding backend built the index.
    func normalizedSimilarities(query: [Float], albumID: String) -> [Float]? {
        let threshold = matchThreshold
        return similarities(query: query, albumID: albumID)?
            .map { max(0, ($0 - threshold) / (1 - threshold)) }
    }

    func topMatches(query: [Float], limit: Int) -> [Match] {
        var out: [Match] = []
        for (albumID, albumVectors) in titleVectors {
            for (i, vector) in albumVectors.enumerated() {
                out.append(Match(albumID: albumID, lessonIndex: i,
                                 score: Self.dot(vector, query)))
            }
        }
        return Array(out.sorted { $0.score > $1.score }.prefix(limit))
    }

    /// Lessons most similar to the given lesson, excluding itself and its
    /// immediate neighbors in the same album.
    func related(albumID: String, lessonIndex: Int, limit: Int) -> [Match] {
        let source = bodyVectors.isEmpty ? titleVectors : bodyVectors
        guard let albumVectors = source[albumID],
              albumVectors.indices.contains(lessonIndex) else { return [] }
        let query = albumVectors[lessonIndex]
        var out: [Match] = []
        for (candidateAlbum, candidateVectors) in source {
            for (i, vector) in candidateVectors.enumerated() {
                if candidateAlbum == albumID && abs(i - lessonIndex) <= 1 { continue }
                out.append(Match(albumID: candidateAlbum, lessonIndex: i,
                                 score: Self.dot(vector, query)))
            }
        }
        return Array(out.sorted { $0.score > $1.score }.prefix(limit))
    }

    // MARK: Cache

    nonisolated private struct CachedVectors: Codable {
        let modified: Date
        let titleBackend: String
        let titles: [[Float]]
        let bodies: [[Float]]?
    }

    nonisolated static func cacheDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                                  in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("AlbumSemanticIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static func loadOrBuildVectors(albumID: String, modified: Date,
                                               titles: [String], bodies: [String],
                                               cacheDir: URL?)
        -> (titles: [[Float]], titleBackend: String, bodies: [[Float]]?)? {
        let cacheURL = cacheDir?.appendingPathComponent(albumID + ".vectors2.json")
        let preferredBackend = sentenceBackendAvailable() ? "sentence" : "contextual"
        if let cacheURL,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(CachedVectors.self, from: data),
           abs(cached.modified.timeIntervalSince(modified)) < 1,
           cached.titles.count == titles.count,
           cached.titleBackend == preferredBackend {
            return (cached.titles, cached.titleBackend, cached.bodies)
        }
        guard let (titleVecs, backend) = embedTitles(titles) else { return nil }
        let bodyVecs = contextualEmbed(bodies)
        if let cacheURL,
           let data = try? JSONEncoder().encode(CachedVectors(modified: modified,
                                                              titleBackend: backend,
                                                              titles: titleVecs,
                                                              bodies: bodyVecs)) {
            try? data.write(to: cacheURL)
        }
        return (titleVecs, backend, bodyVecs)
    }

    // MARK: Embedding backends

    nonisolated static func sentenceBackendAvailable() -> Bool {
        NLEmbedding.sentenceEmbedding(for: .english) != nil
    }

    nonisolated static func embedTitles(_ texts: [String]) -> ([[Float]], String)? {
        if let vectors = sentenceEmbed(texts) { return (vectors, "sentence") }
        if let vectors = contextualEmbed(texts) { return (vectors, "contextual") }
        return nil
    }

    nonisolated static func embedQuery(_ text: String, backend: String) -> [Float]? {
        switch backend {
        case "sentence": sentenceEmbed([text])?.first
        default: contextualEmbed([text])?.first
        }
    }

    nonisolated static func sentenceEmbed(_ texts: [String]) -> [[Float]]? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        return texts.map { text in
            let clipped = String(text.prefix(500))
            guard let vector = embedding.vector(for: clipped) else {
                return [Float](repeating: 0, count: embedding.dimension)
            }
            return normalize(vector.map(Float.init))
        }
    }

    nonisolated static func contextualEmbed(_ texts: [String]) -> [[Float]]? {
        guard let embedding = NLContextualEmbedding(language: .english),
              (try? embedding.load()) != nil else { return nil }
        var out: [[Float]] = []
        for text in texts {
            let clipped = String(text.prefix(1200))
            guard let result = try? embedding.embeddingResult(for: clipped, language: .english) else {
                out.append([Float](repeating: 0, count: embedding.dimension))
                continue
            }
            var sum = [Double](repeating: 0, count: embedding.dimension)
            var count = 0
            result.enumerateTokenVectors(in: clipped.startIndex..<clipped.endIndex) { vector, _ in
                for (i, v) in vector.enumerated() where i < sum.count { sum[i] += v }
                count += 1
                return true
            }
            guard count > 0 else {
                out.append([Float](repeating: 0, count: embedding.dimension))
                continue
            }
            out.append(normalize(sum.map { Float($0 / Double(count)) }))
        }
        return out
    }

    nonisolated static func normalize(_ v: [Float]) -> [Float] {
        let magnitude = v.reduce(Float(0)) { $0 + $1 * $1 }.squareRoot()
        guard magnitude > 0 else { return v }
        return v.map { $0 / magnitude }
    }

    nonisolated static func dot(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else { return 0 }
        var total: Float = 0
        for i in a.indices { total += a[i] * b[i] }
        return total
    }
}
