import Foundation
import Testing
@testable import CosmicDaybook

/// Stand-ins shared by the review-A2 album suites.
enum ShelfReviewFixture {

    /// Stands in for the Trash: moves the file into a folder of its own, or
    /// fails having moved nothing.
    nonisolated final class Trash: @unchecked Sendable {
        let folder: URL
        let fails: Bool
        private let lock = NSLock()
        private var moved: [String] = []

        init(in root: URL, fails: Bool = false) throws {
            folder = root.appendingPathComponent("Trash", isDirectory: true)
            self.fails = fails
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }

        var trashed: [String] { lock.withLock { moved } }

        func move(_ url: URL) throws {
            if fails { throw CocoaError(.fileWriteNoPermission) }
            try FileManager.default.moveItem(at: url, to: folder.appendingPathComponent(url.lastPathComponent))
            lock.withLock { moved.append(url.lastPathComponent) }
        }
    }

    static func setDates(_ url: URL, _ date: Date) throws {
        try FileManager.default.setAttributes([.modificationDate: date, .creationDate: date], ofItemAtPath: url.path)
    }

    static func samePath(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    /// Everything on the shelf, hidden files included.
    static func shelfContents(_ folders: AlbumShelfFixture.Folders) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folders.shelf.path).sorted()
    }
}

/// Review of the 2026-10-17 album fixes, part A: Remove from iCloud when the
/// copy here is older or is the iCloud folder itself (1), Use Newer Copy (3)
/// and what iPhone and iPad call the Trash (12).
@Suite("Albums: removing and replacing albums in iCloud (bug hunt 10-17, review A2)", .serialized)
@MainActor
struct AlbumShelfRemovalFix1017ReviewA2AlbumsTests {
    private typealias Fixture = AlbumShelfFixture
    private typealias Trash = ShelfReviewFixture.Trash

    // MARK: 1 Remove from iCloud

    @Test("Remove from iCloud sends a revised album to the Trash when the copy in a chosen folder is older")
    func olderCopyHereSendsTheShelfCopyToTheTrash() async throws {
        let name = Fixture.albumName("Revised")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let kept = try Fixture.writeAlbum(name, in: folders.shelf, pageCount: 6)
            let older = try Fixture.writeAlbum(name, in: folders.chosen, pageCount: 4)
            let now = Date()
            try ShelfReviewFixture.setDates(kept, now)
            try ShelfReviewFixture.setDates(older, now.addingTimeInterval(-3600))
            let revised = try Data(contentsOf: kept)
            let trash = try Trash(in: folders.root)
            library.trashItem = { try trash.move($0) }
            library.load(from: library.withShelf([folders.chosen]))
            let album = try #require(library.albums.first)
            #expect(library.isKeptInICloud(album))
            guard case .older(let copy) = library.chosenCopy(of: album) else {
                Issue.record("Expected the older copy to be found, got \(library.chosenCopy(of: album))")
                return
            }
            #expect(ShelfReviewFixture.samePath(copy, older))
            #expect(!library.hasCopyInChosenFolders(album))

            await library.removeFromICloud(album)

            #expect(trash.trashed == [name])
            #expect(try Data(contentsOf: trash.folder.appendingPathComponent(name)) == revised)
            #expect(!FileManager.default.fileExists(atPath: kept.path))
            #expect(FileManager.default.fileExists(atPath: older.path))
            #expect(library.shelfError == nil)
        }
    }

    @Test("A chosen folder that is the iCloud folder under another path isn't counted as another copy")
    func shelfUnderAnotherPathIsNotAnotherCopy() async throws {
        let name = Fixture.albumName("Only Copy")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let kept = try Fixture.writeAlbum(name, in: folders.shelf)
            let bytes = try Data(contentsOf: kept)
            // The same folder reached by another path, as a bookmark can resolve it.
            let alias = folders.root.appendingPathComponent("Alias", isDirectory: true)
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: folders.shelf)
            let trash = try Trash(in: folders.root)
            library.trashItem = { try trash.move($0) }
            library.load(from: library.withShelf([alias]))
            let album = try #require(library.albums.first)
            #expect(library.isKeptInICloud(album))
            #expect(library.chosenCopy(of: album) == .missing)

            await library.removeFromICloud(album)

            #expect(trash.trashed == [name])
            #expect(try Data(contentsOf: trash.folder.appendingPathComponent(name)) == bytes)
        }
    }

    @Test("A confirmed Move to Trash moves the album to the Trash even when a copy turns up meanwhile")
    func confirmedTrashIsNeverADelete() async throws {
        let name = Fixture.albumName("Confirmed")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let kept = try Fixture.writeAlbum(name, in: folders.shelf)
            let trash = try Trash(in: folders.root)
            library.trashItem = { try trash.move($0) }
            library.load(from: library.withShelf([folders.chosen]))
            let album = try #require(library.albums.first)
            // The dialog said Move to Trash; then a copy lands in the chosen folder.
            try FileManager.default.copyItem(at: kept, to: folders.chosen.appendingPathComponent(name))

            await library.removeFromICloud(album, mayDelete: false)

            #expect(trash.trashed == [name])
            #expect(FileManager.default.fileExists(atPath: trash.folder.appendingPathComponent(name).path))
        }
    }

    @Test("Remove from iCloud does nothing while the album is being copied")
    func removeWaitsForACopyInProgress() async throws {
        let name = Fixture.albumName("Busy")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let kept = try Fixture.writeAlbum(name, in: folders.shelf)
            let trash = try Trash(in: folders.root)
            library.trashItem = { try trash.move($0) }
            library.load(from: library.withShelf([]))
            let album = try #require(library.albums.first)
            library.albumsBeingKept.insert(album.id)

            await library.removeFromICloud(album)

            library.albumsBeingKept.remove(album.id)
            #expect(FileManager.default.fileExists(atPath: kept.path))
            #expect(trash.trashed.isEmpty)
        }
    }

    // MARK: 3 Use Newer Copy

    /// A shelf copy and a newer copy in the chosen folder, loaded.
    private struct NewerCopy {
        let album: Album
        let kept: URL
        let newer: URL
    }

    private static func loadNewerCopy(
        _ name: String, newerBytes: Data? = nil, into library: AlbumLibrary, folders: AlbumShelfFixture.Folders
    ) throws -> NewerCopy {
        let kept = try Fixture.writeAlbum(name, in: folders.shelf, pageCount: 4)
        let newer: URL
        if let newerBytes {
            newer = folders.chosen.appendingPathComponent(name)
            try newerBytes.write(to: newer)
        } else {
            newer = try Fixture.writeAlbum(name, in: folders.chosen, pageCount: 6)
        }
        let now = Date()
        try ShelfReviewFixture.setDates(kept, now.addingTimeInterval(-3600))
        try ShelfReviewFixture.setDates(newer, now)
        library.load(from: library.withShelf([folders.chosen]))
        let album = try #require(library.albums.first)
        try #require(library.newerCopy(for: album) != nil)
        return NewerCopy(album: album, kept: kept, newer: newer)
    }

    @Test("Use Newer Copy keeps the old copy in the Trash")
    func useNewerCopyTrashesTheOldOne() async throws {
        let name = Fixture.albumName("Revised")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let trash = try Trash(in: folders.root)
            library.trashItem = { try trash.move($0) }
            let setup = try Self.loadNewerCopy(name, into: library, folders: folders)
            let old = try Data(contentsOf: setup.kept)

            await library.useNewerCopy(setup.album)

            #expect(library.shelfError == nil)
            #expect(try Data(contentsOf: setup.kept) == Data(contentsOf: setup.newer))
            #expect(trash.trashed == [name])
            #expect(try Data(contentsOf: trash.folder.appendingPathComponent(name)) == old)
            #expect(try ShelfReviewFixture.shelfContents(folders) == [name])
            #expect(library.albums.first?.pageCount == 6)
        }
    }

    @Test("A newer copy that doesn't open as a PDF leaves the album in iCloud as it was")
    func unreadableNewerCopyChangesNothing() async throws {
        let name = Fixture.albumName("Broken")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let trash = try Trash(in: folders.root)
            library.trashItem = { try trash.move($0) }
            let setup = try Self.loadNewerCopy(
                name, newerBytes: Data("half a download".utf8), into: library, folders: folders
            )
            let old = try Data(contentsOf: setup.kept)

            await library.useNewerCopy(setup.album)

            #expect(try Data(contentsOf: setup.kept) == old)
            #expect(trash.trashed.isEmpty)
            #expect(try ShelfReviewFixture.shelfContents(folders) == [name])
            #expect(library.shelfError?.contains("doesn't open as a PDF") == true)
        }
    }

    @Test("When the old copy can't go to the Trash, Use Newer Copy changes nothing and says so")
    func failedTrashKeepsTheOldCopy() async throws {
        let name = Fixture.albumName("Stays")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            let trash = try Trash(in: folders.root, fails: true)
            library.trashItem = { try trash.move($0) }
            let setup = try Self.loadNewerCopy(name, into: library, folders: folders)
            let old = try Data(contentsOf: setup.kept)

            await library.useNewerCopy(setup.album)

            #expect(try Data(contentsOf: setup.kept) == old)
            #expect(try ShelfReviewFixture.shelfContents(folders) == [name])
            #expect(library.shelfError?.contains(AlbumICloudShelf.trashName) == true)
            #expect(library.albumsBeingKept.isEmpty)
        }
    }

    @Test("A replace whose copy fails partway leaves the album in iCloud as it was")
    func failedReplaceCopyChangesNothing() async throws {
        let folders = try Fixture.Folders()
        defer { try? FileManager.default.removeItem(at: folders.root) }
        let kept = folders.shelf.appendingPathComponent("Botany.pdf")
        try Data("kept".utf8).write(to: kept)
        let newer = folders.chosen.appendingPathComponent("Botany.pdf")
        try Data("newer".utf8).write(to: newer)
        let trash = try Trash(in: folders.root)

        await #expect(throws: CocoaError.self) {
            try await AlbumICloudShelf.replace(kept, with: newer, copy: { _, destination in
                try Data("new".utf8).write(to: destination)
                throw CocoaError(.fileWriteUnknown)
            }, trash: { try trash.move($0) })
        }

        #expect(try Data(contentsOf: kept) == Data("kept".utf8))
        #expect(try ShelfReviewFixture.shelfContents(folders) == ["Botany.pdf"])
        #expect(trash.trashed.isEmpty)
    }

    // MARK: 12 What the Trash is called

    @Test("A failed move to the Trash names it as this device does")
    func trashIsNamedForTheDevice() async throws {
        let name = Fixture.albumName("Named")
        try await Fixture.withLibrary(names: [name]) { library, folders in
            try Fixture.writeAlbum(name, in: folders.shelf)
            let trash = try Trash(in: folders.root, fails: true)
            library.trashItem = { try trash.move($0) }
            library.load(from: library.withShelf([]))
            let album = try #require(library.albums.first)

            await library.removeFromICloud(album)

            #if os(macOS)
            let place = "the Trash"
            #else
            let place = "Recently Deleted in the Files app"
            #endif
            #expect(library.shelfError == "Couldn't move \(album.title) to \(place), so it's still in iCloud.")
        }
    }
}
