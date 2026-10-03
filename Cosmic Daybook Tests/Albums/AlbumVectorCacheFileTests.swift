import Foundation
import NaturalLanguage
import Testing
@testable import CosmicDaybook

/// The semantic index caches each album's vectors as raw Float32 behind a
/// small versioned header (Energy Fifty #42), where it used to keep a JSON
/// file about three times the size whose parse was most of a library load.
/// Every float comes back with its exact bits, a JSON cache from an earlier
/// build is converted once and never embedded again, and the index ranks
/// exactly as it did from the JSON.
@Suite("Album vector cache file", .serialized)
@MainActor
struct AlbumVectorCacheFileTests {

    private static let modified = Date(timeIntervalSinceReferenceDate: 780_123_456.789_012)

    private static func bits(_ rows: [[Float]]?) -> [[UInt32]]? {
        rows?.map { $0.map(\.bitPattern) }
    }

    private static func bits(_ values: [Float]?) -> [UInt32]? {
        values?.map(\.bitPattern)
    }

    /// Unit vectors no embedder would produce, so a vector that comes back
    /// equal to one of these came from the cache, not from embedding.
    private static func randomVectors(_ count: Int, dimension: Int = 512,
                                      using rng: inout some RandomNumberGenerator) -> [[Float]] {
        (0..<count).map { _ in
            AlbumSemanticIndex.normalize((0..<dimension).map { _ in Float.random(in: -1...1, using: &rng) })
        }
    }

    private static func makeCacheDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlbumVectorCacheFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func item(_ id: String, lessons: Int) -> AlbumSemanticIndex.BuildItem {
        AlbumSemanticIndex.BuildItem(
            id: id, modified: modified,
            titles: (0..<lessons).map { "\(id) lesson \($0 + 1)" },
            bodies: (0..<lessons).map { "What the child does in \(id) lesson \($0 + 1)." })
    }

    // MARK: The format

    @Test("Every float, the date and the model name come back with their exact bits")
    func roundTripIsExact() throws {
        let odd: [Float] = [0, -0.0, 1, -1, .leastNonzeroMagnitude, -.leastNormalMagnitude,
                            .greatestFiniteMagnitude, -.infinity, Float(bitPattern: 0x7FC0_1234),
                            0.1, -0.044_194_173]
        let file = AlbumVectorCacheFile(modified: Self.modified, titleBackend: "sentence",
                                        titles: [odd, odd.reversed()], bodies: [odd.map { -$0 }])
        let data = try #require(file.encoded())
        let back = try #require(AlbumVectorCacheFile.decode(data))

        #expect(Self.bits(back.titles) == Self.bits(file.titles))
        #expect(Self.bits(back.bodies) == Self.bits(file.bodies))
        #expect(back.modified.timeIntervalSinceReferenceDate.bitPattern
                == Self.modified.timeIntervalSinceReferenceDate.bitPattern)
        #expect(back.titleBackend == "sentence")
        // A 36-byte header plus the model's name, then four bytes a float.
        #expect(data.count == 36 + "sentence".utf8.count + 3 * odd.count * 4)
    }

    @Test("No body vectors, no lessons and empty rows each come back as they were")
    func shapesSurvive() throws {
        let files = [
            AlbumVectorCacheFile(modified: Self.modified, titleBackend: "sentence",
                                 titles: [[0.5, -0.5]], bodies: nil),
            AlbumVectorCacheFile(modified: Self.modified, titleBackend: "contextual", titles: [], bodies: []),
            AlbumVectorCacheFile(modified: .distantPast, titleBackend: "sentence", titles: [], bodies: nil),
            AlbumVectorCacheFile(modified: .distantFuture, titleBackend: "sentence",
                                 titles: [[], []], bodies: [[]])
        ]
        for file in files {
            let back = try #require(file.encoded().flatMap(AlbumVectorCacheFile.decode))
            #expect(back == file)
        }
    }

    @Test("A short, overlong, foreign or other-version file is a miss, and ragged rows are never written")
    func damagedFilesAreMisses() throws {
        let file = AlbumVectorCacheFile(modified: Self.modified, titleBackend: "sentence",
                                        titles: [[1, 2], [3, 4]], bodies: [[5, 6], [7, 8]])
        let data = try #require(file.encoded())
        #expect(AlbumVectorCacheFile.decode(data) == file)

        #expect(AlbumVectorCacheFile.decode(Data()) == nil)
        #expect(AlbumVectorCacheFile.decode(data.dropLast()) == nil)
        #expect(AlbumVectorCacheFile.decode(data + [0]) == nil)
        var otherVersion = data
        otherVersion[4] = 2
        #expect(AlbumVectorCacheFile.decode(otherVersion) == nil)
        var otherMagic = data
        otherMagic[0] = UInt8(ascii: "X")
        #expect(AlbumVectorCacheFile.decode(otherMagic) == nil)
        let json = try JSONEncoder().encode(LegacyAlbumIndex.CachedVectors(
            modified: Self.modified, titleBackend: "sentence", titles: file.titles, bodies: file.bodies))
        #expect(AlbumVectorCacheFile.decode(json) == nil)

        let ragged = AlbumVectorCacheFile(modified: Self.modified, titleBackend: "sentence",
                                          titles: [[1, 2], [3]], bodies: nil)
        #expect(ragged.encoded() == nil)
    }

    // MARK: Loading an album

    @Test("A JSON cache from an earlier build is converted, not embedded again, and read from the new file after")
    func legacyJSONIsConverted() throws {
        let dir = try Self.makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var rng = SystemRandomNumberGenerator()
        let item = Self.item("Math Album.pdf", lessons: 4)
        try LegacyAlbumIndex.writeVectors(LegacyAlbumIndex.CachedVectors(
            modified: Self.modified, titleBackend: "sentence",
            titles: Self.randomVectors(4, using: &rng), bodies: Self.randomVectors(4, using: &rng)),
            albumID: item.id, in: dir)
        // What an earlier build ranked with.
        let old = try #require(LegacyAlbumIndex.cachedVectors(for: item, backend: "sentence", cacheDir: dir))
        let jsonURL = AlbumVectorCacheFile.legacyJSONURL(for: item.id, in: dir)
        let binaryURL = AlbumVectorCacheFile.url(for: item.id, in: dir)

        let converted = try #require(AlbumSemanticIndex.loadOrBuildVectors(for: item, backend: "sentence",
                                                                           cacheDir: dir))
        #expect(Self.bits(converted.titles) == Self.bits(old.titles))
        #expect(Self.bits(converted.bodies) == Self.bits(old.bodies))
        #expect(converted.titleBackend == "sentence")
        #expect(!FileManager.default.fileExists(atPath: jsonURL.path))
        let written = try binaryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        let reread = try #require(AlbumSemanticIndex.loadOrBuildVectors(for: item, backend: "sentence",
                                                                        cacheDir: dir))
        #expect(Self.bits(reread.titles) == Self.bits(old.titles))
        #expect(Self.bits(reread.bodies) == Self.bits(old.bodies))
        #expect(try binaryURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                == written)
    }

    @Test(
        "A JSON cache for another date or model is not served: the album is embedded and the JSON goes",
        .needsSentenceModel
    )
    func staleLegacyJSONIsReplaced() async throws {
        // Waits out the simulator's lazy sentence-model load.
        try #require(await AlbumSemanticIndex.resolveTitleBackend() == "sentence")
        let dir = try Self.makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var rng = SystemRandomNumberGenerator()
        // One cache from before the PDF last changed, one from the other title model.
        let stale = [
            LegacyAlbumIndex.CachedVectors(modified: Self.modified.addingTimeInterval(-60), titleBackend: "sentence",
                                           titles: Self.randomVectors(2, using: &rng), bodies: nil),
            LegacyAlbumIndex.CachedVectors(modified: Self.modified, titleBackend: "contextual",
                                           titles: Self.randomVectors(2, using: &rng), bodies: nil)
        ]
        for (number, cache) in stale.enumerated() {
            let item = Self.item("Album \(number).pdf", lessons: 2)
            try LegacyAlbumIndex.writeVectors(cache, albumID: item.id, in: dir)

            let built = try #require(AlbumSemanticIndex.loadOrBuildVectors(for: item, backend: "sentence",
                                                                           cacheDir: dir))
            let embedded = try #require(AlbumSemanticIndex.embedTitles(item.titles, backend: "sentence"))
            #expect(Self.bits(built.titles) == Self.bits(embedded))
            #expect(!FileManager.default.fileExists(
                atPath: AlbumVectorCacheFile.legacyJSONURL(for: item.id, in: dir).path))
            let cached = try #require(AlbumVectorCacheFile.read(from: AlbumVectorCacheFile.url(for: item.id, in: dir)))
            #expect(Self.bits(cached.titles) == Self.bits(embedded))
            #expect(cached.fits(modified: Self.modified, titleCount: 2, backend: "sentence"))
        }
    }

    @Test("Rankings from the converted cache are the ones the JSON cache gave", .needsSentenceModel)
    func rankingsAreUnchanged() async throws {
        try #require(await AlbumSemanticIndex.resolveTitleBackend() == "sentence")
        let dir = try Self.makeCacheDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var rng = SystemRandomNumberGenerator()
        let items = [Self.item("Math Album.pdf", lessons: 30), Self.item("Biology Album.pdf", lessons: 20),
                     Self.item("Geometry Album.pdf", lessons: 25)]
        var oldTitles: [String: [[Float]]] = [:]
        var oldBodies: [String: [[Float]]] = [:]
        for item in items {
            try LegacyAlbumIndex.writeVectors(LegacyAlbumIndex.CachedVectors(
                modified: Self.modified, titleBackend: "sentence",
                titles: Self.randomVectors(item.titles.count, using: &rng),
                bodies: Self.randomVectors(item.titles.count, using: &rng)),
                albumID: item.id, in: dir)
            let old = try #require(LegacyAlbumIndex.cachedVectors(for: item, backend: "sentence", cacheDir: dir))
            oldTitles[item.id] = old.titles
            oldBodies[item.id] = old.bodies
        }

        // The first build converts every JSON file; the second reads only the new files.
        let converted = AlbumSemanticIndex()
        await converted.build(items: items, cacheDir: dir)
        let reread = AlbumSemanticIndex()
        await reread.build(items: items, cacheDir: dir)
        #expect(converted.status == .ready)
        #expect(reread.status == .ready)
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).allSatisfy { $0.hasSuffix(".bin") })

        var queries = Self.randomVectors(6, using: &rng)
        queries.append(try #require(oldTitles["Biology Album.pdf"]?[3]))
        for index in [converted, reread] {
            Self.expectRanksLikeJSON(index, titles: oldTitles, bodies: oldBodies, items: items, queries: queries)
        }
    }

    private static func signature(_ matches: [AlbumSemanticIndex.Match]) -> [String] {
        matches.map { "\($0.albumID)#\($0.lessonIndex)=\($0.score.bitPattern)" }
    }

    /// Search matches, per-lesson similarities and Related Lessons, each
    /// against what the old code ranked from the JSON cache's vectors.
    private static func expectRanksLikeJSON(_ index: AlbumSemanticIndex, titles: [String: [[Float]]],
                                            bodies: [String: [[Float]]],
                                            items: [AlbumSemanticIndex.BuildItem], queries: [[Float]]) {
        for query in queries {
            #expect(signature(index.topMatches(query: query, limit: 24))
                    == signature(LegacyAlbumIndex.topMatches(titleVectors: titles, query: query, limit: 24)))
            for item in items {
                #expect(bits(index.similarities(query: query, albumID: item.id))
                        == bits(LegacyAlbumIndex.similarities(titleVectors: titles, query: query, albumID: item.id)))
                #expect(bits(index.normalizedSimilarities(query: query, albumID: item.id))
                        == bits(LegacyAlbumIndex.normalizedSimilarities(
                            titleVectors: titles, matchThreshold: 0.55, query: query, albumID: item.id)))
            }
        }
        for item in items {
            for lesson in [0, 7, item.titles.count - 1] {
                #expect(signature(index.related(albumID: item.id, lessonIndex: lesson, limit: 5))
                        == signature(LegacyAlbumIndex.related(titleVectors: titles, bodyVectors: bodies,
                                                              albumID: item.id, lessonIndex: lesson, limit: 5)))
            }
        }
    }

    // MARK: The embedding loops' pools

    @Test("Sentence vectors are the same with a pool around each text", .needsSentenceModel)
    func pooledSentenceEmbeddingMatches() async throws {
        _ = await AlbumSemanticIndex.resolveTitleBackend()
        let embedding = try #require(NLEmbedding.sentenceEmbedding(for: .english))
        let texts = ["Simple Operations: Subtraction", "Stamp Game Division", "",
                     "Borrowing with the stamp game, then sharing out among the skittles."]
        #expect(Self.bits(AlbumSemanticIndex.sentenceEmbed(texts, with: embedding))
                == Self.bits(LegacyAlbumIndex.sentenceEmbed(texts, with: embedding)))
    }
}
