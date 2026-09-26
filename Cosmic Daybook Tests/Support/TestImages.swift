import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images generated in code for the photo and thumbnail tests, and helpers for
/// comparing what an encoder wrote.
nonisolated enum TestImages {
    /// An opaque image whose quadrants are red (top left), green (top right), blue
    /// (bottom left) and white (bottom right), with a band of varied colour across
    /// the middle so a JPEG of it has real detail to compress.
    static func quadrants(width: Int, height: Int, colorSpace: CFString = CGColorSpace.sRGB) -> CGImage {
        let space = CGColorSpace(name: colorSpace) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { fatalError("Could not create a test bitmap context") }
        let w = CGFloat(width)
        let h = CGFloat(height)
        // Core Graphics puts y = 0 at the bottom, so the top half starts at h / 2.
        let fills: [(CGColor, CGRect)] = [
            (CGColor(red: 1, green: 0, blue: 0, alpha: 1), CGRect(x: 0, y: h / 2, width: w / 2, height: h / 2)),
            (CGColor(red: 0, green: 1, blue: 0, alpha: 1), CGRect(x: w / 2, y: h / 2, width: w / 2, height: h / 2)),
            (CGColor(red: 0, green: 0, blue: 1, alpha: 1), CGRect(x: 0, y: 0, width: w / 2, height: h / 2)),
            (CGColor(red: 1, green: 1, blue: 1, alpha: 1), CGRect(x: w / 2, y: 0, width: w / 2, height: h / 2))
        ]
        for (color, rect) in fills {
            context.setFillColor(color)
            context.fill(rect)
        }
        for column in stride(from: 0, to: width, by: 7) {
            context.setFillColor(CGColor(red: CGFloat(column % 255) / 255, green: 0.5, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: CGFloat(column), y: h * 0.45, width: 3, height: h * 0.1))
        }
        guard let image = context.makeImage() else { fatalError("Could not make a test image") }
        return image
    }

    /// `image` encoded as `type`, tagged with the EXIF `orientation` and any extra
    /// `properties` (camera metadata, resolution).
    static func encoded(
        _ image: CGImage,
        as type: UTType,
        orientation: CGImagePropertyOrientation = .up,
        quality: CGFloat = 0.95,
        properties extra: [CFString: Any] = [:]
    ) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, type.identifier as CFString, 1, nil) else {
            return nil
        }
        var properties = extra
        properties[kCGImagePropertyOrientation] = orientation.rawValue
        properties[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// The pixels an encoded image stores, decoded, with no orientation applied.
    static func stored(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }

    /// An encoded image as a viewer shows it: EXIF orientation applied, full size.
    static func displayed(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(width, height)
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The uniform type identifier of an encoded image ("public.jpeg").
    static func typeIdentifier(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceGetType(source) as String?
    }

    /// The image properties an encoder wrote (orientation, resolution, pixel size).
    static func properties(_ data: Data) -> [CFString: Any] {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return [:] }
        return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
    }

    /// `image` redrawn as 8-bit RGBA in sRGB, row 0 at the top.
    static func rgba(_ image: CGImage) -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(
                      data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                      bytesPerRow: image.width * 4, space: space,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else { return }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return pixels
    }

    /// The quadrant colour at a fraction of `image`'s width and height (y from the
    /// top): "red", "green", "blue", "white", or "other".
    static func color(in image: CGImage, x fractionX: CGFloat, y fractionY: CGFloat) -> String {
        let pixels = rgba(image)
        let x = min(image.width - 1, Int(CGFloat(image.width) * fractionX))
        let y = min(image.height - 1, Int(CGFloat(image.height) * fractionY))
        let offset = (y * image.width + x) * 4
        let channels = pixels[offset..<offset + 3].map { $0 > 200 ? 1 : ($0 < 55 ? 0 : -1) }
        switch channels {
        case [1, 0, 0]: return "red"
        case [0, 1, 0]: return "green"
        case [0, 0, 1]: return "blue"
        case [1, 1, 1]: return "white"
        default: return "other"
        }
    }

    /// The four corner colours of `image` as shown: top left, top right, bottom
    /// left, bottom right.
    static func corners(of image: CGImage) -> [String] {
        [
            color(in: image, x: 0.1, y: 0.1), color(in: image, x: 0.9, y: 0.1),
            color(in: image, x: 0.1, y: 0.9), color(in: image, x: 0.9, y: 0.9)
        ]
    }

    /// A new empty directory under the temporary directory.
    static func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("TestImages-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
