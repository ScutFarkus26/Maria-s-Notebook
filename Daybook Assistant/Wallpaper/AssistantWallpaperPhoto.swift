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
    var fileURL: URL { Self.fileURL(in: directory) }

    /// The saved photo, read from disk once and kept while Photo is the
    /// chosen background (`release(unlessChosen:)`).
    private(set) var image: UIImage?
    @ObservationIgnored private var didLoad = false
    /// Whether a photo is saved: looked for on disk once, then kept by
    /// `save` and `remove`, so the grid's redraws never ask the disk
    /// (`AssistantWallpaper.resolved`; hunt 2026-11-03 #35).
    private(set) var hasPhoto: Bool
    /// Counts the changes to `image`, so a read that finishes after a save,
    /// a remove or a let-go doesn't put an older photo back.
    @ObservationIgnored private var generation = 0
    /// A `preload` is reading the photo off the main thread.
    @ObservationIgnored private(set) var isPreloading = false
    /// The grid wanted the photo while a preload was reading it: if the
    /// preload ends without one, `loadIfNeeded` reads it then.
    @ObservationIgnored private var wantedWhilePreloading = false

    init(directory: URL) {
        self.directory = directory
        hasPhoto = FileManager.default.fileExists(atPath: Self.fileURL(in: directory).path(percentEncoded: false))
    }

    private nonisolated static func fileURL(in directory: URL) -> URL {
        directory.appending(path: "photo.jpg")
    }

    /// Reads the saved photo the first time it's wanted. A read that finds
    /// nothing (no photo yet, or the file still locked just after a restart)
    /// is tried again next time. While a preload is reading it, this waits
    /// for that read rather than decoding it again on the main thread and
    /// throwing the preload's away (bug hunt 2026-11-06 #20).
    func loadIfNeeded() {
        guard !didLoad else { return }
        guard !isPreloading else {
            wantedWhilePreloading = true
            return
        }
        generation += 1
        image = UIImage(contentsOfFile: fileURL.path(percentEncoded: false))
        didLoad = image != nil
        if didLoad { hasPhoto = true }
    }

    /// Reads and decodes the saved photo off the main thread, ahead of the
    /// grid, when Photo is the chosen background (`raw`): its first draw
    /// used to decode about 4 MB on the main thread (hunt 2026-11-03 #33).
    /// If the grid comes first, `loadIfNeeded` reads it then, as before; if
    /// it comes while this reads, it waits for this.
    func preload(chosen raw: String?) async {
        guard raw == AssistantWallpaper.photo.rawValue, hasPhoto, !didLoad, !isPreloading else { return }
        isPreloading = true
        wantedWhilePreloading = false
        let started = generation
        let prepared = await Self.decoded(fileURL)
        isPreloading = false
        if let prepared, generation == started, !didLoad {
            image = prepared
            didLoad = true
        } else if wantedWhilePreloading {
            // The read found nothing, or a save or let-go came meanwhile:
            // the grid that asked still gets what's there now.
            loadIfNeeded()
        }
        wantedWhilePreloading = false
    }

    /// Lets go of the photo when Photo isn't the chosen background (`raw`),
    /// so it isn't held for the rest of the session; the next look reads it
    /// again (hunt 2026-11-03 #33). The picker calls it as it closes.
    func release(unlessChosen raw: String?) {
        guard raw != AssistantWallpaper.photo.rawValue, image != nil || didLoad else { return }
        generation += 1
        image = nil
        didLoad = false
    }

    /// Shrinks and blurs the picked photo off the main thread, saves it, and
    /// shows it.
    func save(_ data: Data) async throws {
        let jpeg = try await Self.prepare(data)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        hasPhoto = true
        generation += 1
        let started = generation
        // Decoded before it's shown, off the main thread, as `preload` does.
        let saved = UIImage(data: jpeg)
        let prepared = await saved?.byPreparingForDisplay()
        guard generation == started else { return }
        image = prepared ?? saved
        didLoad = true
    }

    func remove() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            Self.logger.error("Removing the photo failed: \(error.localizedDescription, privacy: .public)")
        }
        hasPhoto = false
        generation += 1
        image = nil
        didLoad = true
    }

    /// The photo at `url`, decoded ready to draw.
    @concurrent
    nonisolated static func decoded(_ url: URL) async -> UIImage? {
        guard let image = UIImage(contentsOfFile: url.path(percentEncoded: false)) else { return nil }
        return await image.byPreparingForDisplay() ?? image
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
