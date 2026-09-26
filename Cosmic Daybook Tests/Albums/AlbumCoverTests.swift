import CoreGraphics
import Foundation
import PDFKit
import Testing
@testable import CosmicDaybook
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// A library cover is kept as the bitmap PDFKit drew rather than as a TIFF
/// (Mac) or PNG (iOS) copy decoded again on the main actor. The grid must show
/// exactly what it did: the same pixels at the same point size as the image
/// the encoded copy decoded to.
@Suite("Album covers")
@MainActor
struct AlbumCoverTests {

    /// The cover path before 2026-09-26, kept as the reference: render, encode,
    /// decode. Returns the image the grid showed and the encoded bytes it held.
    private func legacyCover(url: URL) -> (image: PlatformImage, encodedBytes: Int)? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        let image = withExtendedLifetime(doc) {
            page.thumbnail(of: CGSize(width: 420, height: 560), for: .mediaBox)
        }
        #if os(macOS)
        let data = image.tiffRepresentation
        #else
        let data = image.pngData()
        #endif
        guard let data, let decoded = PlatformImage(data: data) else { return nil }
        return (decoded, data.count)
    }

    @Test("A cover has the same pixels and point size without the encoded copy")
    func coverMatchesLegacyPixels() throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AlbumTestSupport.writeAlbum(named: "Math Album.pdf", in: dir,
                                                  outline: AlbumTestSupport.sampleOutline)

        let legacy = try #require(legacyCover(url: url))
        let bitmap = try #require(Album.renderCover(url: url))
        let cover = Album.coverImage(from: bitmap)

        #expect(cover.size == legacy.image.size)
        #if os(iOS)
        #expect(cover.scale == legacy.image.scale)
        #endif
        let legacyBitmap = try #require(AlbumTestSupport.bitmap(of: legacy.image))
        let shownBitmap = try #require(AlbumTestSupport.bitmap(of: cover))
        #expect(shownBitmap.width == legacyBitmap.width)
        #expect(shownBitmap.height == legacyBitmap.height)
        let pixels = AlbumTestSupport.rgba(shownBitmap)
        #expect(pixels == AlbumTestSupport.rgba(legacyBitmap))
        // A real render, not two equally blank images: the page's blue block,
        // gold ellipse and text all show.
        #expect(Set(stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }).count > 8)

        // The saving per cover: the encoded copy is no longer held.
        print("AlbumCoverTests: cover \(bitmap.width)x\(bitmap.height) px, "
              + "bitmap \(bitmap.bytesPerRow * bitmap.height) bytes, "
              + "encoded copy no longer held \(legacy.encodedBytes) bytes")
    }

    @Test("A cover dropped by a memory trim is rendered again when the grid asks")
    func releasedCoverIsRequestedAgain() async throws {
        let dir = try AlbumTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = try AlbumTestSupport.writeAlbum(named: "Biology Album.pdf", in: dir,
                                                  outline: AlbumTestSupport.sampleOutline)
        let album = try #require(Album(url: url))
        let library = AlbumLibrary.shared

        library.loadCoverIfNeeded(album)
        #expect(await AlbumTestSupport.waitUntil { album.cover != nil })
        let first = try #require(album.cover.flatMap(AlbumTestSupport.bitmap(of:)))

        // What `releaseMemory(critical:)` does to every album.
        album.releaseCover()
        #expect(album.cover == nil)
        #expect(!album.coverRequested)

        // The card's cover task is keyed on `album.cover == nil`, so the
        // release re-runs it; it asks again and the cover comes back.
        library.loadCoverIfNeeded(album)
        #expect(album.coverRequested)
        #expect(await AlbumTestSupport.waitUntil { album.cover != nil })
        let second = try #require(album.cover.flatMap(AlbumTestSupport.bitmap(of:)))
        #expect(AlbumTestSupport.rgba(second) == AlbumTestSupport.rgba(first))
    }
}
