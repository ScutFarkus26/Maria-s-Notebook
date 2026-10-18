import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CosmicDaybook

// Bug hunt 2026-10-17, #21. An iPhone note photo is stored with its pixels as
// the camera took them and an EXIF orientation tag (`PhotoImageIO.savedPhotoJPEG`).
// The row thumbnail and Apple Intelligence's copy were made without applying
// the tag, so the photo showed (and was described) sideways, and the sideways
// thumbnail was kept in the disk cache.

@Suite("Note photo orientation (Fix1017Ph)")
struct NotePhotoOrientationTests {

    /// A landscape photo stored the way an iPhone held upright stores it: the
    /// pixels sideways, tagged to turn a quarter turn (EXIF 6).
    static func sidewaysPhoto() throws -> Data {
        try #require(TestImages.encoded(TestImages.quadrants(width: 640, height: 480), as: .jpeg, orientation: .right))
    }

    /// Writes `data` into the local note-photo folder under a new name, where
    /// `PhotoStorageService.photoURL(for:)` finds it.
    static func storePhoto(_ data: Data) throws -> String {
        let filename = "fix1017ph-\(UUID().uuidString).jpg"
        try data.write(to: PhotoStorageService.localPhotosDirectory().appendingPathComponent(filename))
        return filename
    }

    @Test("A row thumbnail of a rotated photo comes back upright")
    func rowThumbnailIsUpright() throws {
        let data = try Self.sidewaysPhoto()
        let filename = try Self.storePhoto(data)
        defer { try? PhotoStorageService.deleteLocalImage(filename: filename) }
        let shown = try #require(TestImages.displayed(data))

        let thumbnail = try #require(PhotoStorageService.downsampledCGImage(
            filename: filename, pointSize: CGSize(width: 300, height: 300), scale: 1
        ))

        #expect(thumbnail.height > thumbnail.width, "portrait, as the photo is shown")
        #expect(max(thumbnail.width, thumbnail.height) == 300)
        #expect(TestImages.corners(of: thumbnail) == TestImages.corners(of: shown))
    }

    @Test("Apple Intelligence gets a rotated photo upright")
    func aiImageIsUpright() throws {
        let data = try Self.sidewaysPhoto()
        let filename = try Self.storePhoto(data)
        defer { try? PhotoStorageService.deleteLocalImage(filename: filename) }
        let shown = try #require(TestImages.displayed(data))

        let image = try #require(PhotoStorageService.loadCGImageForAI(filename: filename, maxPixelSize: 320))

        #expect(image.width == 240)
        #expect(image.height == 320)
        #expect(TestImages.corners(of: image) == TestImages.corners(of: shown))
    }

    @Test("A sideways thumbnail cached before the fix isn't reused")
    func oldSidewaysCacheIsNotReused() async throws {
        let directory = try TestImages.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let data = try Self.sidewaysPhoto()
        let filename = try Self.storePhoto(data)
        defer { try? PhotoStorageService.deleteLocalImage(filename: filename) }
        let box = CGSize(width: 300, height: 300)

        // What the old loader cached for this photo: the stored pixels,
        // sideways, under the key AsyncCachedImage used then.
        let sideways = try #require(TestImages.stored(data))
        let cache = ImageDiskCache(directory: directory)
        await Task.detached { cache.save(sideways, pointSize: box, for: "\(filename)_300x300") }.value

        let loaded = try #require(await CachedPhotoLoader.load(
            filename: filename,
            cacheKey: CachedPhotoLoader.cacheKey(filename: filename, pointSize: box),
            pointSize: box,
            scale: 1,
            diskCacheDirectory: directory
        ))

        #expect(!loaded.isFromDiskCache, "made again from the photo")
        #expect(loaded.cgImage.height > loaded.cgImage.width)
        let shown = try #require(TestImages.displayed(data))
        #expect(TestImages.corners(of: loaded.cgImage) == TestImages.corners(of: shown))
    }
}
