import Foundation
import Testing
@testable import CosmicDaybook

/// Scratch folders and clean-up shared by the 10-17 album suites. Each test
/// has a library of its own whose iCloud shelf is a scratch folder (the
/// simulator has no iCloud account), so nothing touches the shared library
/// or the guide's albums.
@MainActor
enum AlbumShelfFixture {

    /// A scratch root with a shelf and a chosen folder in it.
    struct Folders {
        let root: URL
        let shelf: URL
        let chosen: URL

        init() throws {
            root = try AlbumTestSupport.makeDirectory()
            shelf = root.appendingPathComponent("Shelf", isDirectory: true)
            chosen = root.appendingPathComponent("Chosen", isDirectory: true)
            try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
        }
    }

    /// A unique album filename, so caches and first-sighting records left by
    /// the index build can be found and removed.
    static func albumName(_ stem: String) -> String {
        "\(stem) \(UUID().uuidString).pdf"
    }

    @discardableResult
    static func writeAlbum(_ name: String, in folder: URL, pageCount: Int = 4) throws -> URL {
        try AlbumTestSupport.writeAlbum(named: name, in: folder, pageCount: pageCount,
                                        outline: AlbumTestSupport.sampleOutline)
    }

    /// Runs `body` with a library of its own whose shelf is a scratch folder,
    /// then lets the index build its loads started finish and removes what it
    /// left behind for the album files `names`.
    static func withLibrary(
        names: [String], _ body: (AlbumLibrary, Folders) async throws -> Void
    ) async throws {
        let folders = try Folders()
        let library = AlbumLibrary(shelfDirectory: { folders.shelf })
        do {
            try await body(library, folders)
        } catch {
            await finish(library, names: names, folders: folders)
            throw error
        }
        await finish(library, names: names, folders: folders)
    }

    private static func finish(_ library: AlbumLibrary, names: [String], folders: Folders) async {
        _ = await AlbumTestSupport.waitUntil {
            !library.indexing && library.semantic.status != .building && library.shelfDownloadTask == nil
        }
        var lastSeen = UserDefaults.standard.dictionary(forKey: AlbumLibrary.lastSeenKey) as? [String: Double] ?? [:]
        for name in names {
            lastSeen[name] = nil
            let files = [
                AlbumLibrary.indexCacheDirectory()?.appendingPathComponent(name + ".index.json"),
                AlbumSemanticIndex.cacheDirectory().map { AlbumVectorCacheFile.url(for: name, in: $0) }
            ]
            for file in files.compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        UserDefaults.standard.set(lastSeen, forKey: AlbumLibrary.lastSeenKey)
        try? FileManager.default.removeItem(at: folders.root)
    }

    /// Runs `body` with the stored folder bookmarks set to `bookmarks`, and
    /// puts the real list back. Nothing in `body` may suspend, so no other
    /// test sees the list in between.
    static func withStoredBookmarks(_ bookmarks: [Data], _ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: AlbumLibrary.bookmarksKey)
        defaults.set(bookmarks, forKey: AlbumLibrary.bookmarksKey)
        defer { defaults.set(saved, forKey: AlbumLibrary.bookmarksKey) }
        try body()
    }
}

/// Bug hunt 2026-10-17, albums: the iCloud shelf seen on activation (#18), a
/// shelf whose albums are all evicted (#19), a failed Keep in iCloud (#23)
/// and Remove from iCloud with no other copy (#24).
@Suite("Albums: the iCloud shelf (bug hunt 10-17)", .serialized)
@MainActor
struct AlbumShelfFix1017AlTests {
    private typealias Fixture = AlbumShelfFixture

    // MARK: #18 The shelf on activation

    @Test("An album another device keeps in iCloud joins the library on the next activation")
    func shelfAlbumJoinsOnActivation() async throws {
        let chosenName = Fixture.albumName("Chosen")
        let shelfName = Fixture.albumName("Shelf")
        try await Fixture.withLibrary(names: [chosenName, shelfName]) { library, folders in
            try Fixture.writeAlbum(chosenName, in: folders.chosen)

            // The shelf is empty at load, so only the chosen folder is read.
            library.load(from: library.withShelf([folders.chosen]))
            #expect(library.albums.map(\.id) == [chosenName])
            #expect(await AlbumTestSupport.waitUntil { !library.indexing })

            // Another device keeps an album in iCloud; it lands on the shelf here.
            try Fixture.writeAlbum(shelfName, in: folders.shelf)
            library.refreshIfChanged()

            #expect(Set(library.albums.map(\.id)) == [chosenName, shelfName])
            #expect(library.shelfURL?.standardizedFileURL.path == folders.shelf.standardizedFileURL.path)
            #expect(library.removableFolderURLs.map(\.standardizedFileURL.path)
                == [folders.chosen.standardizedFileURL.path])
        }
    }

    @Test("A device that started on Choose the Folder opens the shelf once albums arrive on it")
    func needsFolderOpensTheShelfOnActivation() async throws {
        let shelfName = Fixture.albumName("Arrived")
        try await Fixture.withLibrary(names: [shelfName]) { library, folders in
            try Fixture.withStoredBookmarks([]) {
                library.bootstrapIfNeeded()
                #expect(library.state == .needsFolder)

                try Fixture.writeAlbum(shelfName, in: folders.shelf)
                library.refreshIfChanged()
            }

            #expect(library.state == .ready)
            #expect(library.albums.map(\.id) == [shelfName])
        }
    }

    // MARK: #19 Every shelf album evicted

    @Test("When every shelf album is evicted and none can download, the library says so instead of spinning")
    func evictedShelfThatCannotDownloadSaysSo() async throws {
        let name = Fixture.albumName("Evicted")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let url = try Fixture.writeAlbum(name, in: folders.shelf)
            library.load(from: library.withShelf([]))
            #expect(library.albums.map(\.id) == [name])
            #expect(await AlbumTestSupport.waitUntil { !library.indexing })

            // The system evicts it: only the placeholder is left, and there's no network.
            try FileManager.default.removeItem(at: url)
            try Data("stub".utf8).write(to: UbiquitousFile.placeholderURL(for: url))
            library.downloadAlbum = { _ in nil }
            library.load(from: library.folderURLs)

            // The album that isn't here any more isn't offered to open.
            #expect(library.albums.isEmpty)
            #expect(library.pendingShelfAlbumNames == [name])
            #expect(await AlbumTestSupport.waitUntil { library.shelfDownloadTask == nil })
            guard case .failed(let message) = library.state else {
                Issue.record("Expected the download failure to be shown, got \(library.state)")
                return
            }
            #expect(message.contains("couldn't be downloaded"))
        }
    }

    // MARK: #23 A failed Keep in iCloud

    @Test("A copy to iCloud that fails partway leaves nothing on the shelf under the album's name")
    func failedKeepLeavesNoBrokenAlbum() async throws {
        let folders = try Fixture.Folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let original = folders.chosen.appendingPathComponent("History Album.pdf")
        try Data("history".utf8).write(to: original)

        await #expect(throws: CocoaError.self) {
            try await AlbumICloudShelf.keep(original, on: folders.shelf) { _, destination in
                // The network drops after the first bytes are written.
                try Data("hist".utf8).write(to: destination)
                throw CocoaError(.fileWriteUnknown)
            }
        }

        #expect(AlbumICloudShelf.listing(of: folders.shelf) == .init())
        let left = try FileManager.default.contentsOfDirectory(atPath: folders.shelf.path)
        #expect(left.isEmpty, "Left on the shelf: \(left)")
        #expect(try Data(contentsOf: original) == Data("history".utf8))
    }

    @Test("A copy to iCloud that succeeds leaves only the album on the shelf")
    func keepLeavesOnlyTheAlbum() async throws {
        let folders = try Fixture.Folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let original = folders.chosen.appendingPathComponent("History Album.pdf")
        try Data("history".utf8).write(to: original)

        #expect(try await AlbumICloudShelf.keep(original, on: folders.shelf))

        let left = try FileManager.default.contentsOfDirectory(atPath: folders.shelf.path)
        #expect(left == ["History Album.pdf"])
        #expect(try Data(contentsOf: folders.shelf.appendingPathComponent("History Album.pdf"))
            == Data("history".utf8))
    }

    // MARK: #24 Remove from iCloud

    /// Stands in for the Trash: moves the file into `folder`, or fails.
    nonisolated private final class FakeTrash: @unchecked Sendable {
        let folder: URL
        let fails: Bool
        private(set) var trashed: [String] = []

        init(in root: URL, fails: Bool = false) throws {
            folder = root.appendingPathComponent("Trash", isDirectory: true)
            self.fails = fails
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        func trash(_ url: URL) throws {
            if fails { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
            trashed.append(url.lastPathComponent)
        }
    }

    @Test("Remove from iCloud with no copy in this device's folders moves the album to the Trash")
    func removeWithNoOtherCopyTrashes() async throws {
        let name = Fixture.albumName("Only Copy")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let kept = try Fixture.writeAlbum(name, in: folders.shelf)
            let bytes = try Data(contentsOf: kept)
            let trash = try FakeTrash(in: folders.root)
            library.trashItem = { try trash.trash($0) }
            library.load(from: library.withShelf([]))
            let album = try #require(library.albums.first)
            #expect(!library.hasCopyInChosenFolders(album))

            await library.removeFromICloud(album)

            #expect(trash.trashed == [name])
            #expect(try Data(contentsOf: trash.folder.appendingPathComponent(name)) == bytes)
            #expect(!FileManager.default.fileExists(atPath: kept.path))
            #expect(library.shelfError == nil)
            #expect(library.albums.isEmpty)
        }
    }

    @Test("When the Trash move fails, nothing is deleted and the guide is told")
    func failedTrashDeletesNothing() async throws {
        let name = Fixture.albumName("Stays")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let kept = try Fixture.writeAlbum(name, in: folders.shelf)
            let trash = try FakeTrash(in: folders.root, fails: true)
            library.trashItem = { try trash.trash($0) }
            library.load(from: library.withShelf([]))
            let album = try #require(library.albums.first)

            await library.removeFromICloud(album)

            #expect(FileManager.default.fileExists(atPath: kept.path))
            #expect(library.shelfError
                == "Couldn't move \(album.title) to \(AlbumICloudShelf.trashName), so it's still in iCloud.")
            #expect(library.albums.map(\.id) == [name])
        }
    }

    @Test("With a copy in a chosen folder, Remove from iCloud deletes the shelf copy and that copy takes its place")
    func removeWithAnotherCopyDeletes() async throws {
        let name = Fixture.albumName("Two Copies")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let original = try Fixture.writeAlbum(name, in: folders.chosen)
            let kept = folders.shelf.appendingPathComponent(name)
            try FileManager.default.copyItem(at: original, to: kept)
            let trash = try FakeTrash(in: folders.root)
            library.trashItem = { try trash.trash($0) }
            library.load(from: library.withShelf([folders.chosen]))
            let album = try #require(library.albums.first)
            #expect(library.isKeptInICloud(album))
            #expect(library.hasCopyInChosenFolders(album))

            await library.removeFromICloud(album)

            #expect(trash.trashed.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: kept.path))
            #expect(FileManager.default.fileExists(atPath: original.path))
            let replacement = try #require(library.albums.first)
            #expect(replacement.url.standardizedFileURL.path == original.standardizedFileURL.path)
            #expect(library.shelfError == nil)
        }
    }
}
