import Foundation
import SwiftUI
import ImageIO
import CoreGraphics
import OSLog

#if !os(macOS)
import UIKit
#endif

/// Service for managing photo storage in the app's documents directory
public enum PhotoStorageService {
    nonisolated private static let logger = Logger.photos

    /// Returns the directory URL where note photos are stored.
    /// Uses the app's Documents directory.
    /// Ensures the directory exists before returning.
    nonisolated public static func photosDirectory() throws -> URL {
        let fm = FileManager.default
        
        let documentsURL = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("Note Photos", isDirectory: true)
        
        try createDirectoryIfNeeded(at: documentsURL)
        return documentsURL
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
        guard let photosDir = directory ?? (try? photosDirectory()) else { return nil }
        let fileURL = photosDir.appendingPathComponent(filename, isDirectory: false)
        return PhotoImageIO.preview(contentsOf: fileURL, side: side, scale: scale)
    }
    #endif

    /// Writes JPEG bytes to `directory` under a new UUID filename and returns the filename.
    nonisolated private static func writePhotoJPEG(_ jpegData: Data, in directory: URL) throws -> String {
        let filename = UUID().uuidString + ".jpg"
        let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
        try jpegData.write(to: fileURL)
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
        let photosDir: URL
        do {
            photosDir = try photosDirectory()
        } catch {
            logger.warning("Failed to get photos directory for downsampled image: \(error.localizedDescription)")
            return nil
        }

        let fileURL = photosDir.appendingPathComponent(filename, isDirectory: false)

        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
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
        guard let photosDir = try? photosDirectory() else { return nil }
        let fileURL = photosDir.appendingPathComponent(filename, isDirectory: false)
        guard let imageSource = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary)
    }

    /// Deletes an image file from the photos directory.
    /// - Parameter filename: The filename to delete
    /// - Throws: An error if the file cannot be deleted
    nonisolated public static func deleteImage(filename: String) throws {
        let photosDir = try photosDirectory()
        let fileURL = photosDir.appendingPathComponent(filename, isDirectory: false)
        
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
