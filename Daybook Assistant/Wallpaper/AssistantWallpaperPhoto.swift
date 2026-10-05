import UIKit
import ImageIO
import CoreImage
import OSLog
import Observation

/// Her own photo behind the grid. It stays on this iPhone: never synced, never
/// seen by the guide.
///
/// The photo is shrunk and blurred once, when she picks it, and saved as a
/// small JPEG; drawing the background only shows that file (with a wash that
/// follows light and dark). A live blur would be redone on every frame the
/// grid draws.
@MainActor
@Observable
final class AssistantWallpaperPhoto {
    static let shared = AssistantWallpaperPhoto(
        directory: URL.applicationSupportDirectory.appending(path: "Wallpaper", directoryHint: .isDirectory)
    )

    /// The long side of the saved photo, in pixels: enough for a Pro Max
    /// screen once blurred, and a few hundred KB on disk.
    nonisolated static let longSide = 1200
    nonisolated static let blurRadius = 30.0

    enum ImportError: Error {
        case unreadable
    }

    private static let logger = Logger.app(category: "wallpaper")

    let directory: URL
    var fileURL: URL { directory.appending(path: "photo.jpg") }

    /// The saved photo, read from disk once and kept.
    private(set) var image: UIImage?
    @ObservationIgnored private var didLoad = false

    init(directory: URL) {
        self.directory = directory
    }

    var hasPhoto: Bool {
        FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false))
    }

    /// Reads the saved photo the first time it's wanted. A read that finds
    /// nothing (no photo yet, or the file still locked just after a restart)
    /// is tried again next time.
    func loadIfNeeded() {
        guard !didLoad else { return }
        image = UIImage(contentsOfFile: fileURL.path(percentEncoded: false))
        didLoad = image != nil
    }

    /// Shrinks and blurs the picked photo off the main thread, saves it, and
    /// shows it.
    func save(_ data: Data) async throws {
        let jpeg = try await Self.prepare(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        image = UIImage(data: jpeg)
        didLoad = true
    }

    func remove() {
        do {
            if hasPhoto { try FileManager.default.removeItem(at: fileURL) }
        } catch {
            Self.logger.error("Removing the photo failed: \(error.localizedDescription, privacy: .public)")
        }
        image = nil
        didLoad = true
    }

    /// The picked image, at most `longSide` pixels long, upright, blurred and
    /// as JPEG.
    @concurrent
    nonisolated static func prepare(_ data: Data) async throws -> Data {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { throw ImportError.unreadable }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide
        ] as CFDictionary
        guard let small = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw ImportError.unreadable
        }
        let input = CIImage(cgImage: small)
        // Clamped first, so the blur doesn't pull in transparent edges.
        let blurred = input.clampedToExtent()
            .applyingGaussianBlur(sigma: blurRadius)
            .cropped(to: input.extent)
        let context = CIContext(options: [.cacheIntermediates: false])
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let jpeg = context.jpegRepresentation(
                of: blurred,
                colorSpace: colorSpace,
                options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.8]
              )
        else { throw ImportError.unreadable }
        return jpeg
    }
}
