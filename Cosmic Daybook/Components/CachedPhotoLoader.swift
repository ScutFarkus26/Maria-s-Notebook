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
        // Downsampled so the full-size photo is never decoded
        guard let original = PhotoStorageService.downsampledCGImage(
            filename: filename,
            pointSize: pointSize,
            scale: scale
        ) else { return nil }
        return Loaded(cgImage: original, isFromDiskCache: false, diskCache: diskCache)
    }

    /// The same platform image each path produced before this loader, so what is
    /// drawn is unchanged. From the original: `NSImage(cgImage:size:)` at
    /// `pointSize` / `UIImage` at the screen scale. From the disk cache it was
    /// `NSImage(data:)`, whose size comes from the resolution the file records —
    /// `pointSize` again — and `UIImage(data:)`, which has scale 1.
    private static func platformImage(for loaded: Loaded, pointSize: CGSize, scale: CGFloat) -> PlatformImage {
        #if os(macOS)
        return NSImage(cgImage: loaded.cgImage, size: pointSize)
        #else
        let imageScale: CGFloat = loaded.isFromDiskCache ? 1 : scale
        return UIImage(cgImage: loaded.cgImage, scale: imageScale, orientation: .up)
        #endif
    }
}
