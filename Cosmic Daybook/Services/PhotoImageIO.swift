// PhotoImageIO.swift
// ImageIO-only encoding and decoding for note photos and their caches.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// JPEG encoding and decoding for note photos with ImageIO alone — no `NSImage` /
/// `UIImage` round trip — and none of it tied to the main actor, so callers can run
/// it on a background task.
nonisolated enum PhotoImageIO {
    /// Quality of every JPEG the app writes for a note photo or a cached copy of one:
    /// the 0.8 that the `jpegData(compressionQuality:)` and `.compressionFactor` calls
    /// used.
    static let jpegQuality: CGFloat = 0.8

    /// `image` as JPEG at `jpegQuality`, with any extra destination `properties`
    /// (orientation, resolution).
    static func jpegData(from image: CGImage, properties: [CFString: Any] = [:]) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        var options = properties
        options[kCGImageDestinationLossyCompressionQuality] = jpegQuality
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// The first image in the file at `url`, decoded now on the calling thread
    /// rather than lazily at its first draw, which happens on the main thread.
    static func decodedImage(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        return CGImageSourceCreateImageAtIndex(source, 0, options)
    }
}
