import Foundation
import Testing
@testable import CosmicDaybook

/// Pins how the iCloud album shelf lists, keeps and removes albums. A scratch
/// folder stands in for the container (the simulator has no iCloud account);
/// a pending album is the `.<name>.pdf.icloud` placeholder iOS leaves on disk.
@Suite("iCloud album shelf")
struct AlbumICloudShelfTests {

    private func withScratchDirectory(_ body: (URL) async throws -> Void) async throws {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: directory) }
        try await body(directory)
    }

    @Test("The shelf is Documents/Albums in the container, so it shows in iCloud Drive")
    func shelfLocation() async throws {
        try await withScratchDirectory { container in
            let cache = UbiquityContainerCache(system: .init(identity: { 1 }, containerURL: { container }))
            let shelf = try #require(AlbumICloudShelf.directory(container: cache))
            #expect(shelf.standardizedFileURL.path
                == container.appendingPathComponent("Documents/Albums").standardizedFileURL.path)
        }
    }

    @Test("No iCloud, no shelf")
    func noShelfWithoutICloud() {
        let cache = UbiquityContainerCache(system: .init(identity: { nil }, containerURL: { nil }))
        #expect(AlbumICloudShelf.directory(container: cache) == nil)
    }

    @Test("Downloaded PDFs are ready; placeholders are pending under their real names; other files are ignored")
    func listing() async throws {
        try await withScratchDirectory { shelf in
            try Data("pdf".utf8).write(to: shelf.appendingPathComponent("Biology Album.pdf"))
            try Data("stub".utf8).write(to: shelf.appendingPathComponent(".Geometry Album.pdf.icloud"))
            try Data("x".utf8).write(to: shelf.appendingPathComponent("notes.txt"))
            try Data("x".utf8).write(to: shelf.appendingPathComponent(".DS_Store"))

            let listing = AlbumICloudShelf.listing(of: shelf)
            #expect(listing.ready.map(\.lastPathComponent) == ["Biology Album.pdf"])
            #expect(listing.pending.map(\.lastPathComponent) == ["Geometry Album.pdf"])
            #expect(AlbumLibrary.shelfHasAlbums(shelf))
        }
    }

    @Test("An empty shelf has no albums, so it is not added to the library's folders")
    func emptyShelf() async throws {
        try await withScratchDirectory { shelf in
            #expect(AlbumICloudShelf.listing(of: shelf) == .init())
            #expect(!AlbumLibrary.shelfHasAlbums(shelf))
            #expect(!AlbumLibrary.shelfHasAlbums(nil))
        }
    }

    @Test("Keeping copies the album under its own filename and leaves the original; a taken name is left alone")
    func keepAndRemove() async throws {
        try await withScratchDirectory { root in
            let chosen = root.appendingPathComponent("Chosen", isDirectory: true)
            let shelf = root.appendingPathComponent("Shelf", isDirectory: true)
            try FileManager.default.createDirectory(at: chosen, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: shelf, withIntermediateDirectories: true)
            let original = chosen.appendingPathComponent("History Album.pdf")
            try Data("history".utf8).write(to: original)

            #expect(try await AlbumICloudShelf.keep(original, on: shelf))
            let kept = shelf.appendingPathComponent("History Album.pdf")
            #expect(try Data(contentsOf: kept) == Data("history".utf8))
            #expect(FileManager.default.fileExists(atPath: original.path))
            #expect(AlbumICloudShelf.contains(kept, shelf: shelf))
            #expect(!AlbumICloudShelf.contains(original, shelf: shelf))

            try Data("changed".utf8).write(to: original)
            #expect(try await !AlbumICloudShelf.keep(original, on: shelf))
            #expect(try Data(contentsOf: kept) == Data("history".utf8))

            try await AlbumICloudShelf.remove(kept)
            #expect(!FileManager.default.fileExists(atPath: kept.path))
            #expect(FileManager.default.fileExists(atPath: original.path))
        }
    }
}
