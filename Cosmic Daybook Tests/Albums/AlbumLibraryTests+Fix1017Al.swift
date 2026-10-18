import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, albums: a newer copy in a chosen folder (#25), the
/// semantic index after an album leaves (#27) and folder access (#29).
@Suite("Albums: newer copies, the semantic index and folder access (bug hunt 10-17)", .serialized)
@MainActor
struct AlbumLibraryFix1017AlTests {
    private typealias Fixture = AlbumShelfFixture

    // MARK: #25 A newer copy in a chosen folder

    private static func setModified(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    @Test("A chosen folder's newer copy is offered, and Use Newer Copy puts it on the shelf")
    func newerCopyIsOfferedAndUsed() async throws {
        let name = Fixture.albumName("Revised")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let shelfCopy = try Fixture.writeAlbum(name, in: folders.shelf, pageCount: 4)
            let revised = try Fixture.writeAlbum(name, in: folders.chosen, pageCount: 6)
            let now = Date()
            try Self.setModified(shelfCopy, now.addingTimeInterval(-3600))
            try Self.setModified(revised, now)
            // The old copy goes to the Trash (review A2); the simulator's
            // scratch volume has none, so a stand-in takes it.
            let trash = try ShelfReviewFixture.Trash(in: folders.root)
            library.trashItem = { try trash.move($0) }

            library.load(from: library.withShelf([folders.chosen]))
            let album = try #require(library.albums.first)
            #expect(library.isKeptInICloud(album))
            #expect(album.pageCount == 4)
            let newer = try #require(library.newerCopy(for: album))
            #expect(newer.standardizedFileURL.path == revised.standardizedFileURL.path)

            await library.useNewerCopy(album)

            #expect(try Data(contentsOf: shelfCopy) == Data(contentsOf: revised))
            let updated = try #require(library.albums.first)
            #expect(library.isKeptInICloud(updated))
            #expect(updated.pageCount == 6)
            #expect(library.newerCopy(for: updated) == nil)
            #expect(library.shelfError == nil)
            let left = try FileManager.default.contentsOfDirectory(atPath: folders.shelf.path)
            #expect(left == [name])
        }
    }

    @Test("An older copy in a chosen folder isn't offered")
    func olderCopyIsNotOffered() async throws {
        let name = Fixture.albumName("Current")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let shelfCopy = try Fixture.writeAlbum(name, in: folders.shelf)
            let older = try Fixture.writeAlbum(name, in: folders.chosen)
            let now = Date()
            try Self.setModified(shelfCopy, now)
            try Self.setModified(older, now.addingTimeInterval(-3600))

            library.load(from: library.withShelf([folders.chosen]))
            let album = try #require(library.albums.first)

            #expect(library.newerCopy(for: album) == nil)
        }
    }

    // MARK: #27 The semantic index after an album leaves

    @Test("An album that has left the library leaves the semantic index on the next build")
    func semanticIndexForgetsAlbumsThatLeft() async throws {
        let cacheDir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        // Cached vectors for the model this run uses, so nothing is embedded.
        let backend = await AlbumSemanticIndex.resolveTitleBackend()
        func item(_ id: String, _ vectors: [[Float]]) -> AlbumSemanticIndex.BuildItem {
            AlbumVectorCacheFile(modified: .distantPast, titleBackend: backend, titles: vectors, bodies: vectors)
                .save(albumID: id, in: cacheDir)
            return AlbumSemanticIndex.BuildItem(id: id, modified: .distantPast,
                                                titles: vectors.map { _ in "Lesson" },
                                                bodies: vectors.map { _ in "Body" })
        }
        let renamed = item("Old Name.pdf", [[1, 0], [0, 1]])
        let kept = item("Geometry.pdf", [[1, 0], [0.6, 0.8]])
        let index = AlbumSemanticIndex()

        await index.build(items: [renamed, kept], cacheDir: cacheDir)
        #expect(index.similarities(query: [1, 0], albumID: renamed.id) != nil)

        // The album was renamed, so the next load's list no longer has it.
        await index.build(items: [kept], cacheDir: cacheDir)

        #expect(index.status == .ready)
        #expect(index.similarities(query: [1, 0], albumID: renamed.id) == nil)
        #expect(index.similarities(query: [1, 0], albumID: kept.id) != nil)
        #expect(index.related(albumID: kept.id, lessonIndex: 0, limit: 10).allSatisfy { $0.albumID == kept.id })
    }

    // MARK: #29 Folder access

    /// Counts security-scoped access per folder path.
    private final class AccessLedger {
        private(set) var held: [String: Int] = [:]

        var access: AlbumLibrary.ScopeAccess {
            AlbumLibrary.ScopeAccess(
                start: { [self] url in held[url.standardizedFileURL.path, default: 0] += 1; return true },
                stop: { [self] url in held[url.standardizedFileURL.path, default: 0] -= 1 }
            )
        }

        func count(_ url: URL) -> Int { held[url.standardizedFileURL.path] ?? 0 }
    }

    @Test("Folder access is held once per chosen folder, and given back when the folder is removed")
    func folderAccessIsBalanced() throws {
        let folders = try Fixture.Folders()
        let other = folders.root.appendingPathComponent("Other", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let library = AlbumLibrary(shelfDirectory: { nil })
        let ledger = AccessLedger()
        library.scopeAccess = ledger.access
        let bookmarks = try [folders.chosen, other].map {
            try SecurityScopedBookmark.make(for: $0, unscopedOptions: .minimalBookmark)
        }

        Fixture.withStoredBookmarks(bookmarks) {
            library.bootstrap()
            // Opening the albums again (as a restore does) resolves the folders again.
            library.bootstrap()
            #expect(ledger.count(folders.chosen) == 1)
            #expect(ledger.count(other) == 1)

            library.removeFolder(folders.chosen)
            #expect(ledger.count(folders.chosen) == 0)
            #expect(ledger.count(other) == 1)
        }
    }
}
