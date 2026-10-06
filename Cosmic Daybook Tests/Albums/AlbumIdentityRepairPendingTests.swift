import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #50. The rename repair judged "the old name is
// gone" from the albums on this device. On a device still downloading the
// shelf, an album not yet arrived read as gone, so a copy of it under another
// name took the guide's bookmarks, notes and ink, and its fingerprint was
// dropped from the map. While any album is still downloading the repair now
// waits; the library runs it again once the download lands.

@Suite("Album rename repair waits for downloads")
@MainActor
struct AlbumIdentityRepairPendingTests {

    /// An album seen before under `original`, now on this device only as `onDisk`.
    private struct Shelf {
        let dir: URL
        let suiteName: String
        let defaults: UserDefaults
        let album: Album
        let bookmark: CDAlbumBookmark
        let context: NSManagedObjectContext

        func tearDown() {
            try? FileManager.default.removeItem(at: dir)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeShelf(original: String, onDisk: String) throws -> Shelf {
        let dir = try AlbumTestSupport.makeDirectory()
        let suiteName = "AlbumIdentityRepairPendingTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let url = try AlbumTestSupport.writeAlbum(named: onDisk, in: dir, outline: AlbumTestSupport.sampleOutline)
        let album = try #require(Album(url: url))
        defaults.set([album.fingerprint: original], forKey: UserDefaultsKeys.albumsFingerprints)
        let context = try CoreDataTestHelpers.makeContext()
        let bookmark = CDAlbumBookmark(context: context)
        bookmark.albumID = original
        bookmark.pageIndex = 2
        #expect(CoreDataTestHelpers.save(context))
        return Shelf(
            dir: dir, suiteName: suiteName, defaults: defaults, album: album, bookmark: bookmark, context: context
        )
    }

    @Test("While the original is still downloading, a copy doesn't take its annotations")
    func pendingOriginalKeepsItsAnnotations() throws {
        let shelf = try makeShelf(original: "Math Album.pdf", onDisk: "Math Album copy.pdf")
        defer { shelf.tearDown() }

        let applied = AlbumIdentityRepair.repairRenamedAlbums(
            [shelf.album], pendingNames: ["Math Album.pdf"], in: shelf.context, defaults: shelf.defaults
        )

        #expect(applied.isEmpty)
        #expect(shelf.bookmark.albumID == "Math Album.pdf")
        // Nothing was judged, so the map still knows the original.
        let known = shelf.defaults.dictionary(forKey: UserDefaultsKeys.albumsFingerprints) as? [String: String]
        #expect(known == [shelf.album.fingerprint: "Math Album.pdf"])
    }

    @Test("With nothing downloading, a renamed album still carries its annotations across")
    func renameStillRepairedWhenNothingPending() throws {
        let shelf = try makeShelf(original: "Math Album.pdf", onDisk: "Math.pdf")
        defer { shelf.tearDown() }

        let applied = AlbumIdentityRepair.repairRenamedAlbums(
            [shelf.album], pendingNames: [], in: shelf.context, defaults: shelf.defaults
        )

        #expect(applied == ["Math Album.pdf": "Math.pdf"])
        #expect(shelf.bookmark.albumID == "Math.pdf")
    }
}
