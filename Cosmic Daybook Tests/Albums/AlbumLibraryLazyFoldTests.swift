import Foundation
import Testing
@testable import CosmicDaybook

/// The album library no longer folds every page of every album while it
/// indexes (Energy Fifty #42). The first search that needs an album's folded
/// text builds it (`folded(for:)`) and keeps it until a trim, and the text is
/// the one the old index extracted and cached, so searches find what the eager
/// fold found.
@Suite("Album page text: folded by the first search", .serialized)
@MainActor
struct AlbumLibraryLazyFoldTests {

    /// Text the fold changes: accents, curly quotes, a ligature, capitals.
    private static let phrase = "Élève’s “ﬁrst” Stamp Game Division"
    private static let queries = ["stamp game", "eleve's first", "ÉLÈVE", "skittles", "page 4 division"]
    private static let coolDevice = EnergyPolicy(thermalState: .nominal, isLowPowerMode: false)

    private static func search(_ query: String, in corpus: AlbumSearchCorpus) -> [String] {
        let results = AlbumSearchEngine.search(query: query, corpus: corpus, notes: [], albumFilter: nil)
        return (results.lessonHits + results.pageGroups.flatMap(\.hits)).map {
            "\($0.kind)|\($0.albumID)|\($0.pageIndex)|\($0.lessonTitle)|\($0.snippet)|\($0.score)"
        }
    }

    private static func retrieve(_ question: String, in corpus: AlbumSearchCorpus) -> [String] {
        AlbumSearchEngine.retrieve(question: question, corpus: corpus, limit: 8)
            .map { "\($0.album.id)|\($0.pageIndex)|\($0.score)" }
    }

    @Test("Page text is what the old index extracted and cached, and folds to what it folded")
    func pageTextIsUnchanged() throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AlbumTestSupport.writeAlbum(named: "Math Album.pdf", in: dir, pageCount: 6,
                                                  outline: AlbumTestSupport.sampleOutline, phrase: Self.phrase)
        let oldCache = dir.appendingPathComponent("old", isDirectory: true)
        let newCache = dir.appendingPathComponent("new", isDirectory: true)
        for cache in [oldCache, newCache] {
            try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        }
        let modified = Date(timeIntervalSinceReferenceDate: 780_000_000)

        // First from the PDF, then from each one's cache.
        for _ in 0..<2 {
            let old = LegacyAlbumIndex.loadOrBuildIndex(url: url, modified: modified, cacheDir: oldCache)
            let texts = AlbumLibrary.loadOrBuildIndex(url: url, modified: modified, cacheDir: newCache)
            #expect(texts.count == 6)
            #expect(texts == old.texts)
            #expect(texts.map { $0.folded() } == old.folded)
        }
        // The cache file is unchanged, so each reads the other's.
        #expect(AlbumLibrary.loadOrBuildIndex(url: url, modified: modified, cacheDir: oldCache)
                == LegacyAlbumIndex.loadOrBuildIndex(url: url, modified: modified, cacheDir: newCache).texts)
    }

    @Test("Indexing folds nothing; the first search folds the album and finds what the eager fold found")
    func firstSearchFolds() async throws {
        let library = AlbumLibrary.shared
        try #require(!library.indexing)
        let dir = try AlbumTestSupport.makeDirectory()
        let url = try AlbumTestSupport.writeAlbum(named: "Lazy Fold \(UUID().uuidString).pdf", in: dir,
                                                  pageCount: 6, outline: AlbumTestSupport.sampleOutline,
                                                  phrase: Self.phrase)
        let album = try #require(Album(url: url))
        let saved = SavedLibraryState(library)
        defer {
            saved.restore(library, removingTracesOf: album)
            try? FileManager.default.removeItem(at: dir)
        }

        library.albums = [album]
        await library.buildIndexes(policy: Self.coolDevice)
        let modified = try #require(url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate)
        let old = LegacyAlbumIndex.loadOrBuildIndex(url: url, modified: modified, cacheDir: nil)
        #expect(library.pageTexts[album.id] == old.texts)
        #expect(library.foldedTexts[album.id] == nil)

        let corpus = library.corpus()
        #expect(corpus.albums.map(\.folded) == [old.folded])
        #expect(library.foldedTexts[album.id] == old.folded)
        let eager = AlbumSearchCorpus(albums: [AlbumSearchCorpus.AlbumData(
            id: album.id, title: album.title, subject: album.subject, lessons: album.lessons,
            texts: old.texts, folded: old.folded)])
        for query in Self.queries {
            #expect(Self.search(query, in: corpus) == Self.search(query, in: eager))
            #expect(Self.retrieve(query, in: corpus) == Self.retrieve(query, in: eager))
        }
        #expect(!Self.search("stamp game", in: corpus).isEmpty)
    }

    @Test("A re-index keeps an unchanged album's fold and drops a changed album's")
    func reindexKeepsOnlyCurrentFolds() async throws {
        let library = AlbumLibrary.shared
        try #require(!library.indexing)
        let dir = try AlbumTestSupport.makeDirectory()
        let name = "Lazy Fold \(UUID().uuidString).pdf"
        let url = try AlbumTestSupport.writeAlbum(named: name, in: dir, pageCount: 6,
                                                  outline: AlbumTestSupport.sampleOutline, phrase: Self.phrase)
        let album = try #require(Album(url: url))
        let saved = SavedLibraryState(library)
        defer {
            saved.restore(library, removingTracesOf: album)
            try? FileManager.default.removeItem(at: dir)
        }
        library.albums = [album]
        await library.buildIndexes(policy: Self.coolDevice)
        let firstFold = library.corpus().albums.first?.folded
        #expect(library.foldedTexts[album.id] == firstFold)

        // Nothing changed: the fold stays for the next search.
        await library.buildIndexes(policy: Self.coolDevice)
        #expect(library.foldedTexts[album.id] == firstFold)

        // A revised PDF (a minute newer, with other text) takes its fold with it.
        _ = try AlbumTestSupport.writeAlbum(named: name, in: dir, pageCount: 6,
                                            outline: AlbumTestSupport.sampleOutline, phrase: "Golden Bead Addition")
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(60)],
                                              ofItemAtPath: url.path)
        await library.buildIndexes(policy: Self.coolDevice)
        #expect(library.foldedTexts[album.id] == nil)
        let revised = try #require(library.pageTexts[album.id])
        #expect(revised.joined().contains("Golden Bead Addition"))
        let corpus = library.corpus()
        #expect(corpus.albums.first?.folded == revised.map { $0.folded() })
        #expect(!Self.search("golden bead", in: corpus).isEmpty)
        #expect(Self.search("eleve", in: corpus).isEmpty)
    }
}

/// The shared library's index state, put back after a test that indexes a
/// generated album in it, with the caches and first-sighting record that
/// indexing left for that album.
@MainActor
private struct SavedLibraryState {
    let albums: [Album]
    let pageTexts: [String: [String]]
    let foldedTexts: [String: [String]]
    let indexPurged: Bool
    let indexProgress: Double
    let indexedPageCount: Int
    let semanticWasIdle: Bool

    init(_ library: AlbumLibrary) {
        albums = library.albums
        pageTexts = library.pageTexts
        foldedTexts = library.foldedTexts
        indexPurged = library.indexPurged
        indexProgress = library.indexProgress
        indexedPageCount = library.indexedPageCount
        semanticWasIdle = library.semantic.status == .idle
    }

    func restore(_ library: AlbumLibrary, removingTracesOf album: Album) {
        library.albums = albums
        library.pageTexts = pageTexts
        library.foldedTexts = foldedTexts
        library.indexPurged = indexPurged
        library.indexProgress = indexProgress
        library.indexedPageCount = indexedPageCount
        if semanticWasIdle { library.semantic.purge() }
        let files = [
            AlbumLibrary.indexCacheDirectory()?.appendingPathComponent(album.id + ".index.json"),
            AlbumSemanticIndex.cacheDirectory().map { AlbumVectorCacheFile.url(for: album.id, in: $0) }
        ]
        for file in files.compactMap({ $0 }) {
            try? FileManager.default.removeItem(at: file)
        }
        var lastSeen = UserDefaults.standard.dictionary(forKey: AlbumLibrary.lastSeenKey) as? [String: Double] ?? [:]
        lastSeen[album.id] = nil
        UserDefaults.standard.set(lastSeen, forKey: AlbumLibrary.lastSeenKey)
    }
}
