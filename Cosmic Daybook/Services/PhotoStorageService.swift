import Foundation
import SwiftUI
import ImageIO
import CoreGraphics
import OSLog

#if !os(macOS)
import UIKit
#endif

/// Stores note photos where every device signed in to the same iCloud account
/// can read them.
///
/// **Where.** `Note Photos/` at the root of the app's iCloud container, beside
/// (not inside) its `Documents/` folder: Apple's rule is that only `Documents/`
/// shows in iCloud Drive, so the children's photos sync without appearing in
/// Files or Finder. A note keeps only the filename (`CDNote.imagePath`), so the
/// same name finds the photo on every device. When iCloud Drive is off, photos
/// go to the local `Documents/Note Photos/` as they always did.
///
/// **Older photos.** Until 2026-09-27 every photo stayed in the local folder of
/// the device that took it. `moveLocalPhotosToICloud()` moves them into the
/// container once iCloud is available; reads look in the container first and
/// the local folder second, so a photo is found wherever it is.
///
/// **Downloads.** A photo taken on another device may not be on this one yet
/// (see `UbiquitousFile`); `downloadIfNeeded(filename:)` waits for it before a
/// read, and writes and deletes are coordinated.
public enum PhotoStorageService {
    nonisolated private static let logger = Logger.photos
    nonisolated private static let folderName = "Note Photos"

    /// The local `Documents/Note Photos/` folder, created if needed: where
    /// photos are kept while iCloud Drive is off, and where every photo was
    /// kept before they moved to iCloud.
    nonisolated public static func localPhotosDirectory() throws -> URL {
        let fm = FileManager.default

        let documentsURL = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(folderName, isDirectory: true)

        try createDirectoryIfNeeded(at: documentsURL)
        return documentsURL
    }

    /// `Note Photos/` in the app's iCloud container, created if needed; nil
    /// when iCloud Drive is unavailable. The container URL comes from
    /// `UbiquityContainerCache`, which looks it up off the main thread.
    nonisolated static func iCloudPhotosDirectory(
        container: UbiquityContainerCache = .shared
    ) -> URL? {
        guard let containerURL = container.url() else { return nil }
        let directory = containerURL.appendingPathComponent(folderName, isDirectory: true)
        do {
            try createDirectoryIfNeeded(at: directory)
            return directory
        } catch {
            logger.warning("Couldn't create the iCloud photo folder: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Where a new photo is written: iCloud when available, else local.
    nonisolated public static func photosDirectory() throws -> URL {
        try iCloudPhotosDirectory() ?? localPhotosDirectory()
    }

    /// Where the photo named `filename` is: in iCloud (on this device or still
    /// to download), else in the local folder; nil when neither has it.
    nonisolated static func photoURL(for filename: String) -> URL? {
        if let iCloud = iCloudPhotosDirectory()?.appendingPathComponent(filename, isDirectory: false),
           UbiquitousFile.isAvailable(iCloud) {
            return iCloud
        }
        guard let local = try? localPhotosDirectory().appendingPathComponent(filename, isDirectory: false),
              FileManager.default.fileExists(atPath: local.path) else { return nil }
        return local
    }

    /// Waits until the photo named `filename` is on this device, downloading it
    /// from iCloud first when it was taken on another device and has not
    /// arrived yet. Returns immediately for a photo already here.
    @concurrent
    nonisolated static func downloadIfNeeded(filename: String) async {
        guard let url = photoURL(for: filename), UbiquitousFile.needsDownload(url) else { return }
        _ = await UbiquitousFile.ensureLocal(url)
    }

    /// Moves every photo still in the local folder into iCloud, once iCloud is
    /// available, with `FileManager.setUbiquitous`, Apple's call for moving a
    /// file into iCloud (off the main thread, as its documentation requires). A
    /// name iCloud already has is left where it is; reads find the iCloud copy
    /// first. Returns how many photos moved.
    @concurrent
    @discardableResult
    nonisolated static func moveLocalPhotosToICloud() async -> Int {
        guard let destination = iCloudPhotosDirectory(),
              let local = try? localPhotosDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(
                at: local, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
              ),
              !files.isEmpty else { return 0 }
        var moved = 0
        for file in files {
            let target = destination.appendingPathComponent(file.lastPathComponent, isDirectory: false)
            guard !UbiquitousFile.isAvailable(target) else { continue }
            do {
                try FileManager.default.setUbiquitous(true, itemAt: file, destinationURL: target)
                moved += 1
            } catch {
                let name = file.lastPathComponent
                let reason = error.localizedDescription
                logger.warning("Couldn't move \(name, privacy: .public) to iCloud: \(reason, privacy: .public)")
            }
        }
        let total = files.count
        logger.notice("Moved \(moved, privacy: .public) of \(total, privacy: .public) local note photos to iCloud")
        return moved
    }
    
    /// What became of a picked photo handed to `savePickedPhoto`.
    nonisolated public enum PickedPhotoResult: Sendable {
        /// The bytes aren't an image (where `NSImage(data:)` / `UIImage(data:)` gave nil).
        case notAnImage
        /// Stored in the photos directory as `filename`.
        case saved(filename: String, preview: CGImage?)
        /// An image, but converting or writing it failed.
        case failed(preview: CGImage?, error: any Error)
    }

    /// Stores a picked photo — the bytes PhotosPicker hands over — as the app's
    /// JPEG, and makes the editor's preview of it for a `previewSide`-point square.
    /// ImageIO transcodes the photo on the concurrent executor, so no full-size
    /// `NSImage` / `UIImage` is decoded and the main thread never touches it; the
    /// file is the one decoding into a platform image and saving that wrote
    /// (`PhotoImageIO.savedPhotoJPEG`). The preview is made from that JPEG, so it
    /// shows the photo exactly as the note will. `directory` replaces
    /// `photosDirectory()`.
    @concurrent
    nonisolated public static func savePickedPhoto(
        _ data: Data,
        previewSide: CGFloat,
        scale: CGFloat,
        in directory: URL? = nil
    ) async -> PickedPhotoResult {
        guard PhotoImageIO.containsImage(data) else { return .notAnImage }
        do {
            guard let jpegData = PhotoImageIO.savedPhotoJPEG(from: data) else {
                throw PhotoStorageError.imageConversionFailed
            }
            let filename = try writePhotoJPEG(jpegData, in: directory ?? photosDirectory())
            let preview = PhotoImageIO.preview(from: jpegData, side: previewSide, scale: scale)
            return .saved(filename: filename, preview: preview)
        } catch {
            let preview = PhotoImageIO.preview(from: data, side: previewSide, scale: scale)
            return .failed(preview: preview, error: error)
        }
    }

    #if !os(macOS)
    /// Saves a platform image to the photos directory and returns the filename.
    /// The filename is generated using a UUID to ensure uniqueness.
    /// Used for camera captures, which arrive as a `UIImage`; picked photos go
    /// through `savePickedPhoto`.
    /// - Parameter image: The platform image (UIImage) to save
    /// - Returns: The filename (not the full path) that can be stored in the CDNote model
    /// - Throws: An error if the image cannot be saved
    public static func saveImage(_ image: UIImage) throws -> String {
        // Convert UIImage to JPEG data
        guard let jpegData = image.jpegData(compressionQuality: PhotoImageIO.jpegQuality) else {
            throw PhotoStorageError.imageConversionFailed
        }
        return try writePhotoJPEG(jpegData, in: photosDirectory())
    }

    /// The editor's preview of a photo already in the photos directory (a camera
    /// capture), read from the file at preview size on the concurrent executor.
    /// `directory` replaces `photosDirectory()`.
    @concurrent
    nonisolated public static func preview(
        ofSavedPhoto filename: String,
        side: CGFloat,
        scale: CGFloat,
        in directory: URL? = nil
    ) async -> CGImage? {
        let fileURL = directory.map { $0.appendingPathComponent(filename, isDirectory: false) }
            ?? photoURL(for: filename)
        guard let fileURL else { return nil }
        return PhotoImageIO.preview(contentsOf: fileURL, side: side, scale: scale)
    }
    #endif

    /// Writes JPEG bytes to `directory` under a new UUID filename and returns the
    /// filename. Coordinated, so iCloud never uploads a half-written photo.
    nonisolated private static func writePhotoJPEG(_ jpegData: Data, in directory: URL) throws -> String {
        let filename = UUID().uuidString + ".jpg"
        let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
        try UbiquitousFile.coordinatedWrite(jpegData, to: fileURL)
        return filename
    }

    /// Loads a downsampled image from the photos directory using a filename.
    /// Uses CGImageSource to create thumbnails efficiently, drastically reducing memory usage:
    /// the full-size photo is never decoded, and the thumbnail is decoded on the calling thread.
    /// - Parameters:
    ///   - filename: The filename returned from saveImage
    ///   - pointSize: The desired size in points
    ///   - scale: The display scale factor (see `DisplayScale.current`)
    /// - Returns: The downsampled bitmap (long edge at most `max(pointSize) × scale` pixels) if found, nil otherwise
    nonisolated public static func downsampledCGImage(
        filename: String, pointSize: CGSize, scale: CGFloat
    ) -> CGImage? {
        guard let fileURL = photoURL(for: filename),
              let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }

        let maxPixelSize = max(pointSize.width, pointSize.height) * scale
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]

        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    }

    /// Loads a downsampled CGImage suitable for on-device AI analysis.
    /// Platform-independent; capped at `maxPixelSize` on the long edge to keep
    /// token cost and latency reasonable.
    nonisolated public static func loadCGImageForAI(
        filename: String, maxPixelSize: CGFloat = 1_024
    ) -> CGImage? {
        guard let fileURL = photoURL(for: filename),
              let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    }

    /// Deletes the photo named `filename` wherever it is: from iCloud (a
    /// coordinated delete, which removes it from every device) and from the
    /// local folder.
    /// - Parameter filename: The filename to delete
    /// - Throws: An error if the file cannot be deleted
    nonisolated public static func deleteImage(filename: String) throws {
        if let iCloud = iCloudPhotosDirectory()?.appendingPathComponent(filename, isDirectory: false) {
            try UbiquitousFile.coordinatedDelete(iCloud)
        }
        try deleteLocalImage(filename: filename)
    }

    /// Deletes the photo named `filename` from the local folder only.
    nonisolated static func deleteLocalImage(filename: String) throws {
        let fileURL = try localPhotosDirectory().appendingPathComponent(filename, isDirectory: false)
        let fm = FileManager.default
        if fm.fileExists(atPath: fileURL.path) {
            try fm.removeItem(at: fileURL)
        }
    }
    
    // MARK: - Private Helpers
    
    nonisolated private static func createDirectoryIfNeeded(at url: URL) throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: url.path, isDirectory: &isDir) {
            if !isDir.boolValue {
                // Exists but is not a directory, remove it and create directory
                try fm.removeItem(at: url)
                try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
            }
        } else {
            try fm.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
}

// MARK: - Errors

public enum PhotoStorageError: Error {
    case imageConversionFailed
}
