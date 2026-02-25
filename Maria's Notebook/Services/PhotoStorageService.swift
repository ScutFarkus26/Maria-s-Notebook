import Foundation
import SwiftUI
import ImageIO
import CoreGraphics
import OSLog

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Service for managing photo storage in the app's documents directory
public enum PhotoStorageService {
    private static let logger = Logger.photos

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
    
    /// Saves a platform image to the photos directory and returns the filename.
    /// The filename is generated using a UUID to ensure uniqueness.
    /// - Parameter image: The platform image (UIImage/NSImage) to save
    /// - Returns: The filename (not the full path) that can be stored in the Note model
    /// - Throws: An error if the image cannot be saved
    #if os(macOS)
    public static func saveImage(_ image: NSImage) throws -> String {
        // Convert NSImage to JPEG data
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [NSBitmapImageRep.PropertyKey.compressionFactor: 0.8]) else {
            throw PhotoStorageError.imageConversionFailed
        }
        
        let photosDir = try photosDirectory()
        let filename = UUID().uuidString + ".jpg"
        let fileURL = photosDir.appendingPathComponent(filename, isDirectory: false)
        
        try jpegData.write(to: fileURL)
        
        return filename
    }
    
    /// Loads an image from the photos directory using a filename.
    /// - Parameter filename: The filename returned from saveImage
    /// - Returns: The NSImage if found, nil otherwise
    nonisolated public static func loadImage(filename: String) -> NSImage? {
        let photosDir: URL
        do {
            photosDir = try photosDirectory()
        } catch {
            logger.warning("Failed to get photos directory: \(error.localizedDescription)")
            return nil
        }

        let fileURL = photosDir.appendingPathComponent(filename, isDirectory: false)
        let imageData: Data
        do {
            imageData = try Data(contentsOf: fileURL)
        } catch {
            logger.warning("Failed to load image data for \(filename, privacy: .public): \(error.localizedDescription)")
            return nil
        }

        return NSImage(data: imageData)
    }
    #else
    public static func saveImage(_ image: UIImage) throws -> String {
        // Convert UIImage to JPEG data
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            throw PhotoStorageError.imageConversionFailed
        }
        
        let photosDir = try photosDirectory()
        let filename = UUID().uuidString + ".jpg"
        let fileURL = photosDir.appendingPathComponent(filename, isDirectory: false)
        
        try jpegData.write(to: fileURL)
        
        return filename
    }
    
    /// Loads an image from the photos directory using a filename.
    /// - Parameter filename: The filename returned from saveImage
    /// - Returns: The UIImage if found, nil otherwise
    nonisolated public static func loadImage(filename: String) -> UIImage? {
        let photosDir: URL
        do {
            photosDir = try photosDirectory()
        } catch {
            logger.warning("Failed to get photos directory: \(error.localizedDescription)")
            return nil
        }

        let fileURL = photosDir.appendingPathComponent(filename, isDirectory: false)
        let imageData: Data
        do {
            imageData = try Data(contentsOf: fileURL)
        } catch {
            logger.warning("Failed to load image data for \(filename, privacy: .public): \(error.localizedDescription)")
            return nil
        }

        return UIImage(data: imageData)
    }
    #endif
    
    /// Loads a downsampled image from the photos directory using a filename.
    /// Uses CGImageSource to create thumbnails efficiently, drastically reducing memory usage.
    /// - Parameters:
    ///   - filename: The filename returned from saveImage
    ///   - pointSize: The desired size in points
    ///   - scale: The display scale factor (typically from UIScreen.main.scale or NSScreen.main?.backingScaleFactor)
    /// - Returns: The downsampled NSImage if found, nil otherwise
    #if os(macOS)
    nonisolated public static func loadDownsampledImage(filename: String, pointSize: CGSize, scale: CGFloat) -> NSImage? {
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
        
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        
        return NSImage(cgImage: thumbnail, size: pointSize)
    }
    #else
    /// Loads a downsampled image from the photos directory using a filename.
    /// Uses CGImageSource to create thumbnails efficiently, drastically reducing memory usage.
    /// - Parameters:
    ///   - filename: The filename returned from saveImage
    ///   - pointSize: The desired size in points
    ///   - scale: The display scale factor (typically from UIScreen.main.scale)
    /// - Returns: The downsampled UIImage if found, nil otherwise
    nonisolated public static func loadDownsampledImage(filename: String, pointSize: CGSize, scale: CGFloat) -> UIImage? {
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
        
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            return nil
        }
        
        return UIImage(cgImage: thumbnail, scale: scale, orientation: .up)
    }
    #endif
    
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
    case fileNotFound
    case directoryCreationFailed
}

