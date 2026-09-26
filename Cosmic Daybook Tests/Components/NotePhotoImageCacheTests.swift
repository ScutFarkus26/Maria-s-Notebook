import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CosmicDaybook

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// `AsyncCachedImage`'s caches: the in-memory budget, the disk cache decoding off
/// the main thread, and the disk cache writing the same pixels the old
/// `jpegData` / `tiffRepresentation` writers did.
@Suite("Note photo image cache")
struct NotePhotoImageCacheTests {

    @Test("The in-memory photo cache is capped at 32 MB and 100 images")
    func costLimit() {
        #expect(ImageCache.totalCostLimit == 32 * 1024 * 1024)
        #expect(ImageCache.shared.totalCostLimit == 32 * 1024 * 1024)
        #expect(ImageCache.shared.countLimit == 100)
    }

    @Test("A disk-cache hit is read and decoded off the main thread and shown as before")
    func diskHitDecodesOffMainThread() async throws {
        let directory = try TestImages.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = TestImages.quadrants(width: 600, height: 450)
        let box = CGSize(width: 300, height: 300)
        // No such photo file exists, so only the disk cache can answer.
        let filename = "absent-\(UUID().uuidString).jpg"
        let cacheKey = "\(filename)_300x300"
        defer { ImageCache.shared.removeObject(forKey: cacheKey as NSString) }

        let cache = ImageDiskCache(directory: directory)
        #if os(macOS)
        let shownSize = box
        #else
        let shownSize = CGSize(width: 300, height: 225)
        #endif
        await Task.detached { cache.save(photo, pointSize: shownSize, for: cacheKey) }.value

        // `ImageDiskCache.decodedImage(for:)` traps on the main thread in Debug, and
        // this test runs on the main actor: returning at all means the read and the
        // decode happened elsewhere.
        let loaded = await CachedPhotoLoader.load(
            filename: filename, cacheKey: cacheKey, pointSize: box, scale: 2, diskCacheDirectory: directory
        )
        let decoded = try #require(loaded)
        #expect(decoded.isFromDiskCache)
        #expect(decoded.cgImage.width == 600)
        #expect(decoded.cgImage.height == 450)
        let file = try Data(contentsOf: cache.fileURL(for: cacheKey))
        let fromFile = try #require(TestImages.stored(file))
        #expect(TestImages.rgba(decoded.cgImage) == TestImages.rgba(fromFile))

        let shown = await CachedPhotoLoader.image(
            filename: filename, cacheKey: cacheKey, pointSize: box, scale: 2, diskCacheDirectory: directory
        )
        let image = try #require(shown)
        #if os(macOS)
        // NSImage(data:) of the cache file had the requested box as its size.
        #expect(image.size == box)
        #expect(image.representations.first?.pixelsWide == 600)
        #else
        // UIImage(data:) of the cache file had scale 1.
        #expect(image.scale == 1)
        #expect(image.size == CGSize(width: 600, height: 450))
        #expect(image.cgImage?.width == 600)
        #endif
        #expect(ImageCache.shared.object(forKey: cacheKey as NSString) === image)
    }

    @Test("A cached image written then read keeps its pixel size and the old writer's pixels",
          arguments: [(600, 450), (450, 600), (601, 333), (123, 457)])
    func writtenThenReadMatchesOldWriter(width: Int, height: Int) async throws {
        let directory = try TestImages.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let thumbnail = TestImages.quadrants(width: width, height: height)
        let box = CGSize(width: 300, height: 300)
        let cache = ImageDiskCache(directory: directory)
        let cacheKey = "photo.jpg_300x300"

        #if os(macOS)
        let shownSize = box
        let oldImage = NSImage(cgImage: thumbnail, size: box)
        let oldFile = try #require(Self.oldMacDiskCacheWrite(oldImage))
        #else
        let scale: CGFloat = 2
        let shownSize = CGSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale)
        let oldImage = UIImage(cgImage: thumbnail, scale: scale, orientation: .up)
        let oldFile = try #require(oldImage.jpegData(compressionQuality: 0.8))
        #endif

        await Task.detached { cache.save(thumbnail, pointSize: shownSize, for: cacheKey) }.value
        let newFile = try Data(contentsOf: cache.fileURL(for: cacheKey))
        let decoded = await Task.detached { cache.decodedImage(for: cacheKey) }.value
        let readBack = try #require(decoded)

        #expect(readBack.width == width)
        #expect(readBack.height == height)
        let oldPixels = try #require(TestImages.stored(oldFile))
        let newPixels = try #require(TestImages.stored(newFile))
        #expect(TestImages.rgba(newPixels) == TestImages.rgba(oldPixels))
        #expect(TestImages.rgba(readBack) == TestImages.rgba(oldPixels))
        #if os(macOS)
        #expect(NSImage(data: newFile)?.size == NSImage(data: oldFile)?.size)
        #endif
    }

    #if os(macOS)
    /// The disk-cache writer before `ImageDiskCache.save` used ImageIO.
    private static func oldMacDiskCacheWrite(_ image: NSImage) -> Data? {
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8])
    }
    #endif
}
