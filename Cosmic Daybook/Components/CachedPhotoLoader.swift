// CachedPhotoLoader.swift
// Memory cache, then disk cache, then the photo file — for AsyncCachedImage.

import CoreGraphics
import Foundation

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Where `AsyncCachedImage` gets a note photo at one display size: the in-memory
/// `ImageCache`, then the JPEG disk cache, then the photo file itself. The disk
/// read, every decode and the downsample run off the main thread; only the memory
/// lookup and wrapping the bitmap in a platform image happen on it.
enum CachedPhotoLoader {
    /// A decoded bitmap and where it came from.
    nonisolated struct Loaded: Sendable {
        let cgImage: CGImage
        /// From the JPEG disk cache rather than the photo file.
        let isFromDiskCache: Bool
        /// The disk cache that answered, or that the original is written back to.
        let diskCache: ImageDiskCache?
    }

    /// The memory- and disk-cache key for the photo `filename` shown in a
    /// `pointSize` box: sizes are cached separately. "upright" marks copies made
    /// with the photo's orientation applied (2026-10-17); the sideways copies
    /// cached before then, under the bare size, are never read again.
    nonisolated static func cacheKey(filename: String, pointSize: CGSize) -> String {
        "\(filename)_\(Int(pointSize.width))x\(Int(pointSize.height))_upright"
    }

    /// The image for `cacheKey`, or nil when neither cache has it and the photo
    /// can't be read. `diskCacheDirectory` overrides `ImageDiskCache.standard`.
    static func image(
        filename: String,
        cacheKey: String,
        pointSize: CGSize,
        scale: CGFloat,
        diskCacheDirectory: URL? = nil
    ) async -> PlatformImage? {
        // 1. In-memory cache (fastest)
        if let cached = ImageCache.shared.object(forKey: cacheKey as NSString) {
            return cached
        }

        // 2 + 3. Disk cache, then the photo itself, both read and decoded off the main thread
        guard let loaded = await load(
            filename: filename,
            cacheKey: cacheKey,
            pointSize: pointSize,
            scale: scale,
            diskCacheDirectory: diskCacheDirectory
        ) else { return nil }

        let image = platformImage(for: loaded, pointSize: pointSize, scale: scale)
        ImageCache.shared.setObject(image, forKey: cacheKey as NSString, cost: ImageCache.cost(of: loaded.cgImage))

        if !loaded.isFromDiskCache, let diskCache = loaded.diskCache {
            // Save to disk cache (fire and forget, runs in background)
            let cgImage = loaded.cgImage
            let shownSize = image.size
            Task.detached(priority: .background) {
                diskCache.save(cgImage, pointSize: shownSize, for: cacheKey)
            }
        }
        return image
    }

    /// Steps 2 and 3 of `image(...)`, on the concurrent executor.
    @concurrent
    nonisolated static func load(
        filename: String,
        cacheKey: String,
        pointSize: CGSize,
        scale: CGFloat,
        diskCacheDirectory: URL?
    ) async -> Loaded? {
        let diskCache = diskCacheDirectory.map { ImageDiskCache(directory: $0) } ?? ImageDiskCache.standard
        if let cached = diskCache?.decodedImage(for: cacheKey) {
            return Loaded(cgImage: cached, isFromDiskCache: true, diskCache: diskCache)
        }
        // A photo taken on another device may still be in iCloud; wait for it.
        await PhotoStorageService.downloadIfNeeded(filename: filename)
        // Downsampled so the full-size photo is never decoded
        guard let original = PhotoStorageService.downsampledCGImage(
            filename: filename,
            pointSize: pointSize,
            scale: scale
        ) else { return nil }
        return Loaded(cgImage: original, isFromDiskCache: false, diskCache: diskCache)
    }

    /// The platform image to draw. On the Mac, the bitmap's own shape at the
    /// screen scale: sized to the square `pointSize` box, an upright photo was
    /// squeezed (review of the 2026-10-17 fixes, a2 #13). On iPhone and iPad,
    /// as before: `UIImage` at the screen scale from the original, and scale 1
    /// from the disk cache (what `UIImage(data:)` gave).
    private static func platformImage(for loaded: Loaded, pointSize: CGSize, scale: CGFloat) -> PlatformImage {
        #if os(macOS)
        let pixelsPerPoint = max(scale, 1)
        return NSImage(cgImage: loaded.cgImage, size: CGSize(
            width: CGFloat(loaded.cgImage.width) / pixelsPerPoint,
            height: CGFloat(loaded.cgImage.height) / pixelsPerPoint
        ))
        #else
        let imageScale: CGFloat = loaded.isFromDiskCache ? 1 : scale
        return UIImage(cgImage: loaded.cgImage, scale: imageScale, orientation: .up)
        #endif
    }
}
