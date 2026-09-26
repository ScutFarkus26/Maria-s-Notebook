// ImageDiskCache.swift
// On-disk JPEG copies of the downsampled note photos AsyncCachedImage shows.

import CoreGraphics
import Foundation
import ImageIO
import OSLog

/// The on-disk copy of every downsampled note photo `AsyncCachedImage` has shown
/// (`Caches/ImageCache/<key>.jpg`), so a photo seen before comes back without
/// opening its full-size original. Reads and writes do file I/O and JPEG coding:
/// call them off the main thread (Debug builds trap when they aren't).
nonisolated struct ImageDiskCache: Sendable {
    private static let logger = Logger.photos

    let directory: URL

    /// `Caches/ImageCache`, created when missing; nil when it can't be.
    static var standard: ImageDiskCache? {
        guard let cachesDirectory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = cachesDirectory.appendingPathComponent("ImageCache", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                logger.error("[\(#function)] Failed to create cache directory: \(error)")
                return nil
            }
        }
        return ImageDiskCache(directory: directory)
    }

    /// The file for `cacheKey`. Slashes and colons become underscores, which is how
    /// the files already on disk are named.
    func fileURL(for cacheKey: String) -> URL {
        let safeFilename = cacheKey.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return directory.appendingPathComponent("\(safeFilename).jpg")
    }

    /// The cached image for `cacheKey`, read and fully decoded on the calling
    /// thread, or nil when there is none.
    func decodedImage(for cacheKey: String) -> CGImage? {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(.main))
        #endif
        let url = fileURL(for: cacheKey)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let image = PhotoImageIO.decodedImage(at: url) else {
            Self.logger.error("[\(#function)] Failed to decode cached image \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        return image
    }

    /// Stores `image` for `cacheKey` as a JPEG at quality 0.8, like the
    /// `jpegData(compressionQuality:)` and `NSBitmapImageRep` writers it replaces
    /// (a file from either decodes to the same pixels). `pointSize` — the size the
    /// app shows the image at — is written as the file's resolution, as
    /// `NSBitmapImageRep` did, so `NSImage(data:)` still reads the file back at
    /// that size.
    func save(_ image: CGImage, pointSize: CGSize, for cacheKey: String) {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(.main))
        #endif
        var properties: [CFString: Any] = [:]
        if pointSize.width > 0, pointSize.height > 0 {
            properties[kCGImagePropertyDPIWidth] = 72 * CGFloat(image.width) / pointSize.width
            properties[kCGImagePropertyDPIHeight] = 72 * CGFloat(image.height) / pointSize.height
        }
        guard let data = PhotoImageIO.jpegData(from: image, properties: properties) else {
            Self.logger.error("[\(#function)] Failed to encode image for disk cache")
            return
        }
        do {
            try data.write(to: fileURL(for: cacheKey), options: .atomic)
        } catch {
            Self.logger.error("[\(#function)] Failed to save image to disk cache: \(error)")
        }
    }
}
