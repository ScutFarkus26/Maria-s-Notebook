import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CosmicDaybook

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Attaching a photo to a note. The saved JPEG must match what the old path wrote
/// after decoding the photo into an `NSImage` / `UIImage` (kept here as
/// `oldSave`), and the editors' previews must hold only the pixels their frames
/// need.
@Suite("Note photo attachment")
struct NotePhotoAttachmentTests {

    nonisolated struct Input: CustomTestStringConvertible, Sendable {
        let type: UTType
        let orientation: CGImagePropertyOrientation

        var testDescription: String {
            "\(type.preferredFilenameExtension ?? type.identifier), EXIF orientation \(orientation.rawValue)"
        }
    }

    nonisolated static let inputs: [Input] = [
        Input(type: .jpeg, orientation: .up),
        Input(type: .jpeg, orientation: .right),
        Input(type: .jpeg, orientation: .left),
        Input(type: .jpeg, orientation: .down),
        Input(type: .heic, orientation: .up),
        Input(type: .heic, orientation: .right),
        Input(type: .png, orientation: .leftMirrored),
        Input(type: .png, orientation: .right)
    ]

    /// Location and camera metadata an iPhone photo carries.
    static let cameraMetadata: [CFString: Any] = [
        kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 37.33, kCGImagePropertyGPSLatitudeRef: "N"],
        kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone"],
        kCGImagePropertyDPIWidth: 72,
        kCGImagePropertyDPIHeight: 72
    ]

    /// The save path this replaced: decode into a platform image, then encode that.
    static func oldSave(_ data: Data) -> Data? {
        #if os(macOS)
        guard let image = NSImage(data: data),
              let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmapImage.representation(
            using: .jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.8]
        )
        #else
        return UIImage(data: data)?.jpegData(compressionQuality: 0.8)
        #endif
    }

    @Test("A picked photo is saved at the old path's size, orientation and pixels", arguments: inputs)
    func savedPhotoMatchesOldPath(_ input: Input) throws {
        let photo = TestImages.quadrants(width: 640, height: 480)
        let data = try #require(TestImages.encoded(
            photo, as: input.type, orientation: input.orientation, properties: Self.cameraMetadata
        ))
        let old = try #require(Self.oldSave(data))
        let new = try #require(PhotoImageIO.savedPhotoJPEG(from: data))

        let oldProperties = TestImages.properties(old)
        let newProperties = TestImages.properties(new)
        #expect(TestImages.typeIdentifier(new) == UTType.jpeg.identifier)
        for key in [kCGImagePropertyPixelWidth, kCGImagePropertyPixelHeight, kCGImagePropertyOrientation,
                    kCGImagePropertyDPIWidth, kCGImagePropertyDPIHeight] {
            #expect(newProperties[key] as? Int == oldProperties[key] as? Int, "\(key)")
        }
        #expect(newProperties[kCGImagePropertyGPSDictionary] == nil)

        // Shown upright it is the same picture, turned the same way.
        let oldShown = try #require(TestImages.displayed(old))
        let newShown = try #require(TestImages.displayed(new))
        #expect(newShown.width == oldShown.width)
        #expect(newShown.height == oldShown.height)
        #expect(TestImages.corners(of: newShown) == TestImages.corners(of: oldShown))
        if input.type != .png {
            // The right way round, too. (UIKit ignores the EXIF orientation of a PNG
            // whose EXIF carries camera tags, and the saved file follows UIKit.)
            let photoShown = try #require(TestImages.displayed(data))
            #expect(TestImages.corners(of: newShown) == TestImages.corners(of: photoShown))
        }

        // Pixel for pixel what the old path stored.
        let oldPixels = try #require(TestImages.stored(old))
        let newPixels = try #require(TestImages.stored(new))
        #expect(TestImages.rgba(newPixels) == TestImages.rgba(oldPixels))
    }

    @Test("The editors' previews hold only the pixels their frames need, upright")
    func previewSizeIsCapped() throws {
        let photo = TestImages.quadrants(width: 2016, height: 1512)
        let data = try #require(TestImages.encoded(photo, as: .jpeg, orientation: .right))
        let photoShown = try #require(TestImages.displayed(data))
        let frames: [(side: CGFloat, scale: CGFloat)] = [
            (NotePhotoPreview.editorSide, 2), (NotePhotoPreview.editorSide, 3), (NotePhotoPreview.quickNoteSide, 2)
        ]
        for frame in frames {
            let preview = try #require(PhotoImageIO.preview(from: data, side: frame.side, scale: frame.scale))
            let shortEdge = CGFloat(min(preview.width, preview.height))
            let longEdge = CGFloat(max(preview.width, preview.height))
            // Still covers its aspect-fill square at the screen's scale...
            #expect(shortEdge >= frame.side * frame.scale)
            // ...and no bigger than that needs (the photo is 4:3).
            #expect(longEdge <= (frame.side * frame.scale * 4 / 3).rounded(.up))
            // Portrait, as the rotated photo is shown.
            #expect(preview.height > preview.width)
            #expect(TestImages.corners(of: preview) == TestImages.corners(of: photoShown))
        }
    }

    @Test("Saving a picked photo writes the transcoded JPEG and returns its preview")
    func savePickedPhotoWritesTheJPEG() async throws {
        let directory = try TestImages.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = TestImages.quadrants(width: 640, height: 480)
        let data = try #require(TestImages.encoded(photo, as: .heic, orientation: .right))

        let result = await PhotoStorageService.savePickedPhoto(data, previewSide: 60, scale: 2, in: directory)

        guard case .saved(let filename, let preview) = result else {
            Issue.record("Expected the photo to be saved, got \(result)")
            return
        }
        #expect(filename.hasSuffix(".jpg"))
        let file = try Data(contentsOf: directory.appendingPathComponent(filename))
        #expect(file == PhotoImageIO.savedPhotoJPEG(from: data))
        let shown = try #require(preview)
        #expect(min(shown.width, shown.height) == 120)
    }

    @Test("Bytes that aren't an image save nothing")
    func notAnImage() async throws {
        let directory = try TestImages.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let result = await PhotoStorageService.savePickedPhoto(
            Data("not a photo".utf8), previewSide: 60, scale: 2, in: directory
        )

        guard case .notAnImage = result else {
            Issue.record("Expected .notAnImage, got \(result)")
            return
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test("The Mac's upright redraw matches ImageIO's rotation for each EXIF orientation",
          arguments: UInt32(1)...UInt32(8))
    func uprightBitmapMatchesImageIO(orientationValue: UInt32) throws {
        let orientation = try #require(CGImagePropertyOrientation(rawValue: orientationValue))
        let data = try #require(TestImages.encoded(
            TestImages.quadrants(width: 64, height: 48), as: .png, orientation: orientation
        ))
        let stored = try #require(TestImages.stored(data))

        let upright = try #require(PhotoImageIO.uprightBitmap(stored, orientation: orientation))
        let imageIO = try #require(TestImages.displayed(data))

        #expect(upright.width == imageIO.width)
        #expect(upright.height == imageIO.height)
        #expect(TestImages.rgba(upright) == TestImages.rgba(imageIO))
    }

    #if !os(macOS)
    @Test("A camera capture's preview is read from the saved file at preview size, upright")
    func cameraPreviewFromSavedFile() async throws {
        let directory = try TestImages.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let capture = UIImage(cgImage: TestImages.quadrants(width: 1600, height: 1200), scale: 1, orientation: .right)
        let saved = try #require(capture.jpegData(compressionQuality: PhotoImageIO.jpegQuality))
        try saved.write(to: directory.appendingPathComponent("capture.jpg"))

        let preview = await PhotoStorageService.preview(
            ofSavedPhoto: "capture.jpg", side: NotePhotoPreview.editorSide, scale: 2, in: directory
        )

        let shown = try #require(preview)
        #expect(shown.width == 120)
        #expect(shown.height == 160)
        let savedShown = try #require(TestImages.displayed(saved))
        #expect(TestImages.corners(of: shown) == TestImages.corners(of: savedShown))
    }
    #endif
}
