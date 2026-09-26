// PhotoImageIO.swift
// ImageIO encoding and decoding for note photos and their caches.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

#if !os(macOS)
import UIKit
#endif

/// JPEG encoding and decoding for note photos with ImageIO — no `NSImage` /
/// `UIImage` decode round trip — and none of it tied to the main actor, so callers
/// can run it on a background task.
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

    // MARK: - Picked photos

    /// Whether `data` holds an image ImageIO can read — the case in which
    /// `NSImage(data:)` / `UIImage(data:)` returned an image.
    static func containsImage(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
        return CGImageSourceGetCount(source) > 0
    }

    /// The JPEG the app stores for a picked photo, transcoded from the photo's bytes
    /// without decoding it into an `NSImage` / `UIImage`. It matches what decoding
    /// into one and encoding that wrote:
    /// - iOS (`UIImage(data:)` → `jpegData(compressionQuality: 0.8)`): the stored
    ///   pixels as they are, tagged with the orientation `UIImage` gave the photo,
    ///   72 dpi. That orientation is read from a `UIImage` made from the bytes,
    ///   which decodes nothing: UIKit, unlike ImageIO's properties, ignores the
    ///   EXIF orientation of a PNG whose EXIF also carries camera or GPS tags.
    /// - macOS (`NSImage(data:)` → `tiffRepresentation` → `NSBitmapImageRep` →
    ///   JPEG 0.8): `NSImage` applies the orientation, so the pixels are written
    ///   upright with no tag, and a resolution other than 72 dpi is kept.
    ///
    /// Neither carried the photo's other metadata (camera EXIF, GPS), and this
    /// doesn't either. The photo is decoded once, while the JPEG is encoded.
    static func savedPhotoJPEG(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCache: false] as CFDictionary
              ) else { return nil }
        #if os(macOS)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let orientation = (properties[kCGImagePropertyOrientation] as? UInt32)
            .flatMap(CGImagePropertyOrientation.init(rawValue:)) ?? .up
        guard let upright = uprightBitmap(image, orientation: orientation)
            ?? fullSizeTransformedImage(source, properties: properties) else { return nil }
        return jpegData(from: upright, properties: keptResolution(properties, orientation: orientation))
        #else
        guard let orientation = UIImage(data: data).map({ exifOrientation($0.imageOrientation) }) else {
            return nil
        }
        return jpegData(from: image, properties: [
            kCGImagePropertyOrientation: orientation.rawValue,
            kCGImagePropertyDPIWidth: 72,
            kCGImagePropertyDPIHeight: 72
        ])
        #endif
    }

    #if !os(macOS)
    /// The EXIF orientation that `jpegData(compressionQuality:)` writes for a
    /// UIKit orientation (the cases correspond one to one).
    private static func exifOrientation(_ orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .upMirrored: return .upMirrored
        case .down: return .down
        case .downMirrored: return .downMirrored
        case .left: return .left
        case .leftMirrored: return .leftMirrored
        case .right: return .right
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
    #endif

    // MARK: - Previews

    /// Long-edge pixel size of a preview drawn aspect-fill into a square of `side`
    /// points: the smallest whose short edge still covers the square at `scale`, so
    /// it looks as sharp there as the full photo did.
    static func previewMaxPixelSize(side: CGFloat, scale: CGFloat, sourcePixelSize: CGSize) -> CGFloat {
        let longEdge = max(sourcePixelSize.width, sourcePixelSize.height)
        let shortEdge = min(sourcePixelSize.width, sourcePixelSize.height)
        guard shortEdge > 0 else { return (side * scale).rounded(.up) }
        return (side * scale * longEdge / shortEdge).rounded(.up)
    }

    /// A preview of the image in `data` for a `side`-point square (aspect fill), its
    /// orientation applied, decoded now on the calling thread. ImageIO decodes it at
    /// preview size, never the full photo.
    static func preview(from data: Data, side: CGFloat, scale: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return preview(from: source, side: side, scale: scale)
    }

    /// `preview(from:side:scale:)` for an image file.
    static func preview(contentsOf url: URL, side: CGFloat, scale: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return preview(from: source, side: side, scale: scale)
    }

    private static func preview(from source: CGImageSource, side: CGFloat, scale: CGFloat) -> CGImage? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        let pixelSize = CGSize(
            width: properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            height: properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        )
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: previewMaxPixelSize(
                side: side, scale: scale, sourcePixelSize: pixelSize
            )
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    // MARK: - Orientation

    /// `image` — pixels as stored — drawn upright for its EXIF `orientation` into a
    /// new plain bitmap: pixel for pixel the bitmap `NSImage(data:)` made, which is
    /// what the Mac's `tiffRepresentation` path encoded. Nil for pixel formats this
    /// doesn't redraw: float, CMYK, gray with alpha, indexed.
    ///
    /// Two ImageIO details decide "pixel for pixel". An image still backed by its
    /// source file, even an upright one, goes down a different JPEG encoder path, so
    /// the pixels are always redrawn. And above about a megapixel ImageIO decodes a
    /// JPEG differently into an opaque bitmap than into one with alpha: `NSImage`
    /// kept an upright photo's alpha layout and made an opaque bitmap when it turned
    /// one, so this does the same.
    static func uprightBitmap(_ image: CGImage, orientation: CGImagePropertyOrientation) -> CGImage? {
        guard let space = image.colorSpace,
              let bitmapInfo = redrawBitmapInfo(for: image, model: space.model, upright: orientation == .up)
        else { return nil }
        let swapsAxes = orientation.swapsAxes
        let width = swapsAxes ? image.height : image.width
        let height = swapsAxes ? image.width : image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: image.bitsPerComponent,
            bytesPerRow: 0, space: space, bitmapInfo: bitmapInfo
        ) else { return nil }
        context.interpolationQuality = .none
        context.concatenate(orientation.drawingTransform(width: CGFloat(width), height: CGFloat(height)))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// Bitmap layout for redrawing `image` without changing its depth or colour
    /// space, or nil when no bitmap context takes it as is. Colour with alpha, or
    /// an `upright` photo, gets a premultiplied alpha channel (see `uprightBitmap`).
    private static func redrawBitmapInfo(for image: CGImage, model: CGColorSpaceModel, upright: Bool) -> UInt32? {
        guard image.bitsPerComponent == 8 || image.bitsPerComponent == 16,
              !image.bitmapInfo.contains(.floatComponents) else { return nil }
        let hasAlpha: Bool
        switch image.alphaInfo {
        case .none, .noneSkipLast, .noneSkipFirst: hasAlpha = false
        default: hasAlpha = true
        }
        switch model {
        case .rgb:
            let alpha: CGImageAlphaInfo = hasAlpha || upright ? .premultipliedLast : .noneSkipLast
            let byteOrder: CGBitmapInfo = image.bitsPerComponent == 16 ? .byteOrder16Little : []
            return alpha.rawValue | byteOrder.rawValue
        case .monochrome where !hasAlpha:
            let byteOrder: CGBitmapInfo = image.bitsPerComponent == 16 ? .byteOrder16Little : []
            return CGImageAlphaInfo.none.rawValue | byteOrder.rawValue
        default:
            return nil
        }
    }

    #if os(macOS)
    /// ImageIO's own upright, full-size rendering — the fallback for pixel formats
    /// `uprightBitmap` doesn't redraw.
    private static func fullSizeTransformedImage(_ source: CGImageSource, properties: [CFString: Any]) -> CGImage? {
        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard width > 0, height > 0 else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The source's resolution for the upright image (width and height trade places
    /// when the orientation turns it a quarter turn), as `NSBitmapImageRep` wrote
    /// it: only when it isn't 72 dpi.
    private static func keptResolution(
        _ properties: [CFString: Any],
        orientation: CGImagePropertyOrientation
    ) -> [CFString: Any] {
        guard let dpiWidth = properties[kCGImagePropertyDPIWidth] as? Double,
              let dpiHeight = properties[kCGImagePropertyDPIHeight] as? Double,
              dpiWidth != 72 || dpiHeight != 72 else { return [:] }
        let swapsAxes = orientation.swapsAxes
        return [
            kCGImagePropertyDPIWidth: swapsAxes ? dpiHeight : dpiWidth,
            kCGImagePropertyDPIHeight: swapsAxes ? dpiWidth : dpiHeight
        ]
    }
    #endif
}
