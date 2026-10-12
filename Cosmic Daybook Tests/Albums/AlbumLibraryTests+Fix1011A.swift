import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11, albums: the index build when the album list changes
/// under it (#54), lesson links on titles an outline repeats (#55), Find a
/// Different Page (#56), the activation check (#58), saved folder access
/// (#63) and search row ids (#64).
@Suite("Albums: index builds, links and folders (bug hunt 10-11)", .serialized)
@MainActor
struct AlbumLibraryFix1011ATests {

    private static let cool = EnergyPolicy(thermalState: .nominal, isLowPowerMode: false)
    private static let cooled = EnergyPolicy.Inputs(thermalState: .nominal, isLowPowerModeEnabled: false)

    /// Albums with the sample outline (lessons on pages 0–3), in a fresh folder.
    private static func makeAlbums(_ names: [String], in dir: URL) throws -> [Album] {
        let tag = UUID().uuidString
        return try names.map { name in
            let url = try AlbumTestSupport.writeAlbum(named: "\(name) \(tag).pdf", in: dir, pageCount: 6,
                                                      outline: AlbumTestSupport.sampleOutline)
            return try #require(Album(url: url))
        }
    }

    // MARK: #54 The index build

    @Test("An album list reloaded mid-build doesn't crash the build, and the new album is indexed after it")
    func reloadMidBuildBuildsAgain() async throws {
        let library = AlbumLibrary.shared
        try #require(!library.indexing)
        let dir = try AlbumTestSupport.makeDirectory()
        let albums = try Self.makeAlbums(["Reload A", "Reload B", "Reload C"], in: dir)
        let saved = SavedIndexState(library)
        defer {
            saved.restore(library, removingTracesOf: albums)
            try? FileManager.default.removeItem(at: dir)
        }

        library.albums = [albums[0], albums[1]]
        let hot = EnergyPolicy(thermalState: .critical, isLowPowerMode: false)
        let build = Task { await library.buildIndexes(policy: hot) }
        // Paused for heat after the first album, as the iPad's first Albums
        // visit can be while shelf downloads finish.
        #expect(await AlbumTestSupport.waitUntil { library.indexEnergyWait != nil })
        #expect(library.pageTexts[albums[0].id]?.count == 6)

        // What `load(from:)` ends with when another album arrives: a new list
        // with an album that has no page text yet, and a build request.
        library.albums = albums
        library.startIndexBuild()
        for _ in 0..<20 { await Task.yield() }

        hot.simulate(Self.cooled)
        await build.value
        for _ in 0..<20 { await Task.yield() }

        #expect(library.pageTexts[albums[2].id]?.count == 6)
        #expect(!library.indexing)
        #expect(library.indexReady)
    }

    @Test("A memory purge mid-build leaves the index marked purged, never half built")
    func purgeMidBuildStaysPurged() async throws {
        let library = AlbumLibrary.shared
        try #require(!library.indexing)
        let dir = try AlbumTestSupport.makeDirectory()
        let albums = try Self.makeAlbums(["Purge A", "Purge B"], in: dir)
        let saved = SavedIndexState(library)
        defer {
            saved.restore(library, removingTracesOf: albums)
            try? FileManager.default.removeItem(at: dir)
        }

        library.albums = albums
        let hot = EnergyPolicy(thermalState: .critical, isLowPowerMode: false)
        let build = Task { await library.buildIndexes(policy: hot) }
        #expect(await AlbumTestSupport.waitUntil { library.indexEnergyWait != nil })

        // Critical memory pressure drops the first album's text mid-build.
        library.releaseMemory(critical: true)
        hot.simulate(Self.cooled)
        await build.value

        // Still purged, so `ensureIndexed()` builds again on the next search.
        #expect(library.indexPurged)
        #expect(!library.indexReady)

        await library.buildIndexes(policy: Self.cool)
        #expect(!library.indexPurged)
        #expect(library.pageTexts[albums[0].id]?.count == 6)
        #expect(library.pageTexts[albums[1].id]?.count == 6)
    }

    // MARK: #55 Re-resolving links

    /// An album whose outline repeats a title, as the real albums repeat
    /// "Extensions" and "Introduction".
    private static func repeatedTitleAlbum(in dir: URL, extensionsPages: [Int], pageCount: Int = 8) throws -> Album {
        var outline = [AlbumTestSupport.OutlineEntry(title: "Introduction", page: 0)]
        outline += extensionsPages.map { AlbumTestSupport.OutlineEntry(title: "Extensions", page: $0) }
        outline.append(AlbumTestSupport.OutlineEntry(title: "The Checkerboard", page: pageCount - 1))
        outline.sort { $0.page < $1.page }
        let url = try AlbumTestSupport.writeAlbum(named: "Math Album.pdf", in: dir, pageCount: pageCount,
                                                  outline: outline)
        return try #require(Album(url: url))
    }

    private static func linkedLesson(_ title: String, page: Int, album: Album,
                                     in context: NSManagedObjectContext) -> CDLesson {
        let lesson = CDLesson(context: context)
        lesson.name = title
        lesson.albumLink = AlbumLink(albumID: album.id, pageIndex: page, lessonTitle: title)
        return lesson
    }

    @Test("A link on a title the outline repeats stays on its own page")
    func repeatedTitleKeepsItsPage() throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let album = try Self.repeatedTitleAlbum(in: dir, extensionsPages: [2, 5])
        let context = try CoreDataTestHelpers.makeContext()
        let second = Self.linkedLesson("Extensions", page: 5, album: album, in: context)
        context.safeSave()

        let moved = LessonAlbumMatcher.reresolvePages(in: album, context: context)

        #expect(moved == 0)
        #expect(second.albumPageIndex == 5)
    }

    @Test("A link whose page no longer has its title moves to the nearest page that does")
    func shiftedLinkMovesToNearest() throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        // A revised PDF moved the second "Extensions" from page 5 to page 6.
        let album = try Self.repeatedTitleAlbum(in: dir, extensionsPages: [2, 6])
        let context = try CoreDataTestHelpers.makeContext()
        let second = Self.linkedLesson("Extensions", page: 5, album: album, in: context)
        let checkerboard = Self.linkedLesson("The Checkerboard", page: 3, album: album, in: context)
        context.safeSave()

        let moved = LessonAlbumMatcher.reresolvePages(in: album, context: context)

        #expect(moved == 2)
        #expect(second.albumPageIndex == 6)
        #expect(checkerboard.albumPageIndex == 7)
    }

    // MARK: #56 Find a Different Page

    @Test("Find a Different Page on a linked lesson offers the other page with its title")
    func differentPageForLinkedLesson() async throws {
        let library = AlbumLibrary.shared
        let dir = try AlbumTestSupport.makeDirectory()
        let outline = [
            AlbumTestSupport.OutlineEntry(title: "Multiplication with the Checkerboard", page: 1),
            AlbumTestSupport.OutlineEntry(title: "Bank Game", page: 2),
            AlbumTestSupport.OutlineEntry(title: "Multiplication with the Checkerboard", page: 4)
        ]
        let url = try AlbumTestSupport.writeAlbum(named: "Different Page \(UUID().uuidString).pdf", in: dir,
                                                  pageCount: 6, outline: outline)
        let album = try #require(Album(url: url))
        let savedAlbums = library.albums
        defer {
            library.albums = savedAlbums
            try? FileManager.default.removeItem(at: dir)
        }
        library.albums = [album]
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = Self.linkedLesson("Multiplication with the Checkerboard", page: 1, album: album, in: context)
        context.safeSave()

        // The single-lesson sheet behind "Find a Different Page…".
        let offered = await LessonAlbumMatchSheet.candidates(for: [lesson], library: library)
        #expect(offered.map(\.pageIndex) == [4])

        // The matcher leaves a linked lesson's current page out.
        let matched = await LessonAlbumMatcher.candidates(for: [lesson], library: library,
                                                          includeAlreadyLinked: true)
        #expect(matched.map(\.pageIndex) == [4])
    }

    // MARK: #58 The activation check

    @Test("A PDF that can't be opened doesn't make every activation reload the library")
    func unopenablePDFDoesNotReload() async throws {
        let library = AlbumLibrary.shared
        try #require(!library.indexing)
        let dir = try AlbumTestSupport.makeDirectory()
        let albums = try Self.makeAlbums(["Refresh A"], in: dir)
        try Data("not a PDF".utf8).write(to: dir.appendingPathComponent("Damaged \(UUID().uuidString).pdf"))
        let saved = SavedIndexState(library)
        let savedState = library.state
        defer {
            library.removeFolder(dir)
            library.state = savedState
            saved.restore(library, removingTracesOf: albums)
            try? FileManager.default.removeItem(at: dir)
        }

        library.load(from: [dir])
        let loaded = try #require(library.albums.first)
        #expect(library.albums.count == 1)
        #expect(await AlbumTestSupport.waitUntil {
            !library.indexing && library.modDates[loaded.id] != nil
        })

        library.refreshIfChanged()

        #expect(library.state == .ready)
        #expect(library.albums.first === loaded)
        // Let the build the load started finish before the folder goes.
        #expect(await AlbumTestSupport.waitUntil { library.semantic.status != .building })
    }

    // MARK: #63 Saved folder access

    private static let reachable = Data("reachable".utf8)
    private static let sameFolderAgain = Data("same folder again".utf8)
    private static let unplugged = Data("unplugged drive".utf8)
    private static let albumsFolder = URL(fileURLWithPath: "/Albums", isDirectory: true)

    private static func resolve(_ data: Data) -> URL? {
        data == unplugged ? nil : albumsFolder
    }

    @Test("Adding a folder keeps the saved access of a folder that can't be reached right now")
    func unreachableFolderKeptOnAdd() {
        let result = AlbumLibrary.dedupedBookmarks([Self.unplugged, Self.reachable, Self.sameFolderAgain],
                                                   resolve: Self.resolve)
        #expect(result.kept == [Self.unplugged, Self.reachable])
        #expect(result.folders == [Self.albumsFolder])
    }

    @Test("Removing a folder keeps the saved access of a folder that can't be reached right now")
    func unreachableFolderKeptOnRemove() {
        let kept = AlbumLibrary.bookmarks([Self.unplugged, Self.reachable],
                                          removingFolderAt: Self.albumsFolder.standardizedFileURL.path,
                                          resolve: Self.resolve)
        #expect(kept == [Self.unplugged])
    }

    // MARK: #64 Search row ids

    @Test("Two outline entries with one title on one page give search rows of their own")
    func repeatedLessonTitlesHaveDistinctIDs() {
        let lessons = [
            AlbumLessonRef(title: "Extensions", pageIndex: 3, depth: 0),
            AlbumLessonRef(title: "Extensions", pageIndex: 3, depth: 1)
        ]
        let texts = Array(repeating: "Extensions of the bead frame", count: 5)
        let corpus = AlbumSearchCorpus(albums: [AlbumSearchCorpus.AlbumData(
            id: "Math Album.pdf", title: "Math", subject: .math, lessons: lessons,
            texts: texts, folded: texts.map { $0.folded() })])

        let results = AlbumSearchEngine.search(query: "extensions", corpus: corpus, notes: [], albumFilter: nil)

        #expect(results.lessonHits.count == 2)
        #expect(Set(results.lessonHits.map(\.id)).count == results.lessonHits.count)
        #expect(Set(lessons.map(\.id)).count == lessons.count)
    }
}

/// The shared library's index state, put back after a test that indexes
/// generated albums in it, with the caches and first-sighting records that
/// indexing left for them.
@MainActor
private struct SavedIndexState {
    let albums: [Album]
    let pageTexts: [String: [String]]
    let indexPurged: Bool
    let indexProgress: Double
    let indexedPageCount: Int
    let semanticWasIdle: Bool

    init(_ library: AlbumLibrary) {
        albums = library.albums
        pageTexts = library.pageTexts
        indexPurged = library.indexPurged
        indexProgress = library.indexProgress
        indexedPageCount = library.indexedPageCount
        semanticWasIdle = library.semantic.status == .idle
    }

    func restore(_ library: AlbumLibrary, removingTracesOf generated: [Album]) {
        library.albums = albums
        library.pageTexts = pageTexts
        library.folds.dropAll()
        library.indexPurged = indexPurged
        library.indexProgress = indexProgress
        library.indexedPageCount = indexedPageCount
        if semanticWasIdle { library.semantic.purge() }
        var lastSeen = UserDefaults.standard.dictionary(forKey: AlbumLibrary.lastSeenKey) as? [String: Double] ?? [:]
        for album in generated {
            library.modDates[album.id] = nil
            library.updatedAlbumIDs.remove(album.id)
            lastSeen[album.id] = nil
            let files = [
                AlbumLibrary.indexCacheDirectory()?.appendingPathComponent(album.id + ".index.json"),
                AlbumSemanticIndex.cacheDirectory().map { AlbumVectorCacheFile.url(for: album.id, in: $0) }
            ]
            for file in files.compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        UserDefaults.standard.set(lastSeen, forKey: AlbumLibrary.lastSeenKey)
    }
}
