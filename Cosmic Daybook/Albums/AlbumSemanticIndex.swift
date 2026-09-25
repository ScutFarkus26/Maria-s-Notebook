import Foundation
import NaturalLanguage
import OSLog
import Synchronization

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
@Observable
final class AlbumSemanticIndex {
    enum Status: Equatable { case idle, building, ready, unavailable }

    var status: Status = .idle
    /// albumID → one vector per entry of Album.lessons.
    private var titleVectors: [String: [[Float]]] = [:]
    private var bodyVectors: [String: [[Float]]] = [:]
    private var titleBackend = ""

    /// Below this cosine score a query match is noise, not meaning.
    var matchThreshold: Float { titleBackend == "sentence" ? 0.55 : 0.88 }

    /// One album's per-lesson text, handed to `build` so the index can embed it.
    nonisolated struct BuildItem: Sendable {
        let id: String
        let modified: Date
        let titles: [String]
        let bodies: [String]
    }

    /// The vectors for one album: one title vector per lesson, the backend that
    /// produced them, and the body vectors when the contextual embedder was
    /// available.
    nonisolated struct VectorSet: Sendable {
        let titles: [[Float]]
        let titleBackend: String
        let bodies: [[Float]]?
    }

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

    func build(items: [BuildItem]) async {
        guard status != .building else { return }
        status = .building
        let cacheDir = Self.cacheDirectory()
        // One title model for every album: queries are embedded with one
        // model, so an album built with the other could never match them.
        // Detached so the wait for the model is never cut short.
        let backend = await Task.detached(priority: .utility) {
            await Self.resolveTitleBackend()
        }.value
        var anySucceeded = false
        for item in items {
            let result = await Task.detached(priority: .utility) {
                Self.loadOrBuildVectors(for: item, backend: backend, cacheDir: cacheDir)
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

    /// `backend` is the title model `resolveTitleBackend()` chose for this
    /// process; a cache built with the other model is rebuilt, and an album
    /// the chosen model can't embed is left out rather than mixed in.
    nonisolated static func loadOrBuildVectors(for item: BuildItem, backend: String,
                                               cacheDir: URL?) -> VectorSet? {
        let (modified, titles, bodies) = (item.modified, item.titles, item.bodies)
        let cacheURL = cacheDir?.appendingPathComponent(item.id + ".vectors2.json")
        if let cacheURL,
           let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(CachedVectors.self, from: data),
           abs(cached.modified.timeIntervalSince(modified)) < 1,
           cached.titles.count == titles.count,
           cached.titleBackend == backend {
            return VectorSet(titles: cached.titles, titleBackend: cached.titleBackend,
                             bodies: cached.bodies)
        }
        guard let titleVecs = embedTitles(titles, backend: backend) else { return nil }
        let bodyVecs = contextualEmbed(bodies)
        if let cacheURL,
           let data = try? JSONEncoder().encode(CachedVectors(modified: modified,
                                                              titleBackend: backend,
                                                              titles: titleVecs,
                                                              bodies: bodyVecs)) {
            try? data.write(to: cacheURL)
        }
        return VectorSet(titles: titleVecs, titleBackend: backend, bodies: bodyVecs)
    }

    // MARK: Embedding backends

    nonisolated static func sentenceBackendAvailable() -> Bool {
        NLEmbedding.sentenceEmbedding(for: .english) != nil
    }

    /// The title model for this process: "sentence" when that model exists,
    /// else "contextual". Decided once, before the first build, so every
    /// album in a launch uses the same one. On the iOS 27 simulator the
    /// sentence model loads lazily — the first request in a process returns
    /// nil and one ~100 ms later returns it (the Mac returns it at once, and
    /// NLEmbedding has no way to request its assets) — so a nil is retried
    /// for up to 2 s. A model that is truly absent costs that wait once.
    nonisolated static func resolveTitleBackend() async -> String {
        if let resolved = resolvedTitleBackend.withLock({ $0 }) { return resolved }
        var available = sentenceBackendAvailable()
        var retries = 0
        while !available, retries < 40 {
            try? await Task.sleep(for: .milliseconds(50))
            retries += 1
            available = sentenceBackendAvailable()
        }
        let backend = available ? "sentence" : "contextual"
        resolvedTitleBackend.withLock { $0 = backend }
        Logger.albums.notice(
            "Album title model: \(backend, privacy: .public) after \(retries, privacy: .public) retries"
        )
        return backend
    }

    nonisolated private static let resolvedTitleBackend = Mutex<String?>(nil)

    nonisolated static func embedTitles(_ texts: [String], backend: String) -> [[Float]]? {
        backend == "sentence" ? sentenceEmbed(texts) : contextualEmbed(texts)
    }

    nonisolated static func embedQuery(_ text: String, backend: String) -> [Float]? {
        queryEmbedders.withLock { models in
            switch backend {
            case "sentence":
                if models.sentence == nil {
                    models.sentence = NLEmbedding.sentenceEmbedding(for: .english)
                }
                guard let embedding = models.sentence else { return nil }
                return sentenceEmbed([text], with: embedding).first
            default:
                if models.contextual == nil {
                    models.contextual = loadedContextualEmbedding()
                }
                guard let embedding = models.contextual else { return nil }
                return contextualEmbed([text], with: embedding).first
            }
        }
    }

    /// The embedding models a query uses, created on the first search and
    /// kept so each keystroke's query doesn't load a model again. At most one
    /// of each; `releaseQueryEmbedders()` drops them under memory pressure.
    /// Queries run one at a time under the lock, so the models are never used
    /// from two threads at once.
    nonisolated private struct QueryEmbedders: ~Copyable {
        var sentence: NLEmbedding?
        var contextual: NLContextualEmbedding?
    }

    nonisolated private static let queryEmbedders = Mutex(QueryEmbedders())

    /// Drops the cached query models; the next search recreates them.
    nonisolated static func releaseQueryEmbedders() {
        queryEmbedders.withLock { models in
            models.sentence = nil
            models.contextual = nil
        }
    }

    /// Whether a query model is currently cached (tests read this).
    nonisolated static var hasCachedQueryEmbedder: Bool {
        queryEmbedders.withLock { $0.sentence != nil || $0.contextual != nil }
    }

    nonisolated static func sentenceEmbed(_ texts: [String]) -> [[Float]]? {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else { return nil }
        return sentenceEmbed(texts, with: embedding)
    }

    nonisolated static func sentenceEmbed(_ texts: [String], with embedding: NLEmbedding) -> [[Float]] {
        texts.map { text in
            let clipped = String(text.prefix(500))
            guard let vector = embedding.vector(for: clipped) else {
                return [Float](repeating: 0, count: embedding.dimension)
            }
            return normalize(vector.map(Float.init))
        }
    }

    nonisolated static func contextualEmbed(_ texts: [String]) -> [[Float]]? {
        guard let embedding = loadedContextualEmbedding() else { return nil }
        return contextualEmbed(texts, with: embedding)
    }

    /// The English contextual model, loaded; `nil` when it isn't available.
    nonisolated static func loadedContextualEmbedding() -> NLContextualEmbedding? {
        guard let embedding = NLContextualEmbedding(language: .english),
              (try? embedding.load()) != nil else { return nil }
        return embedding
    }

    nonisolated static func contextualEmbed(_ texts: [String], with embedding: NLContextualEmbedding) -> [[Float]] {
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
