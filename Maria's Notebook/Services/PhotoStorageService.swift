import Foundation
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Service for managing photo storage in the app's documents directory
public enum PhotoStorageService {
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
        guard let photosDir = try? photosDirectory() else {
            return nil
        }
        
        let fileURL = photosDir.appendingPathComponent(filename, isDirectory: false)
        guard let imageData = try? Data(contentsOf: fileURL) else {
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
        guard let photosDir = try? photosDirectory() else {
            return nil
        }
        
        let fileURL = photosDir.appendingPathComponent(filename, isDirectory: false)
        guard let imageData = try? Data(contentsOf: fileURL) else {
            return nil
        }
        
        return UIImage(data: imageData)
    }
    #endif
    
    /// Deletes an image file from the photos directory.
    /// - Parameter filename: The filename to delete
    /// - Throws: An error if the file cannot be deleted
    public static func deleteImage(filename: String) throws {
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

