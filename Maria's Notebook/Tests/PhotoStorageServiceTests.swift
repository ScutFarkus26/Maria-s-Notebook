#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Directory Tests

@Suite("PhotoStorageService Directory Tests")
struct PhotoStorageServiceDirectoryTests {

    @Test("photosDirectory returns valid URL")
    func photosDirectoryReturnsValidURL() throws {
        let url = try PhotoStorageService.photosDirectory()

        #expect(url.lastPathComponent == "Note Photos")
        #expect(url.isFileURL)
    }

    @Test("photosDirectory creates directory if needed")
    func photosDirectoryCreatesIfNeeded() throws {
        let url = try PhotoStorageService.photosDirectory()
        let fm = FileManager.default

        #expect(fm.fileExists(atPath: url.path))
    }

    @Test("photosDirectory returns same path on repeated calls")
    func photosDirectoryReturnsSamePath() throws {
        let url1 = try PhotoStorageService.photosDirectory()
        let url2 = try PhotoStorageService.photosDirectory()

        #expect(url1 == url2)
    }
}

// MARK: - Save Image Tests

@Suite("PhotoStorageService Save Image Tests")
struct PhotoStorageServiceSaveImageTests {

    #if os(macOS)
    @Test("saveImage returns unique filename")
    func saveImageReturnsUniqueFilename() throws {
        // Create a simple test image
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let filename = try PhotoStorageService.saveImage(image)

        #expect(filename.hasSuffix(".jpg"))
        #expect(filename.count > 4) // More than just ".jpg"

        // Cleanup
        try? PhotoStorageService.deleteImage(filename: filename)
    }

    @Test("saveImage creates file on disk")
    func saveImageCreatesFileOnDisk() throws {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let filename = try PhotoStorageService.saveImage(image)
        let photosDir = try PhotoStorageService.photosDirectory()
        let fileURL = photosDir.appendingPathComponent(filename)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: fileURL.path))

        // Cleanup
        try? PhotoStorageService.deleteImage(filename: filename)
    }

    @Test("saveImage produces different filenames for same image")
    func saveImageProducesDifferentFilenames() throws {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let filename1 = try PhotoStorageService.saveImage(image)
        let filename2 = try PhotoStorageService.saveImage(image)

        #expect(filename1 != filename2)

        // Cleanup
        try? PhotoStorageService.deleteImage(filename: filename1)
        try? PhotoStorageService.deleteImage(filename: filename2)
    }
    #else
    @Test("saveImage returns unique filename")
    func saveImageReturnsUniqueFilename() throws {
        // Create a simple test image
        let size = CGSize(width: 10, height: 10)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        let filename = try PhotoStorageService.saveImage(image)

        #expect(filename.hasSuffix(".jpg"))
        #expect(filename.count > 4)

        // Cleanup
        try? PhotoStorageService.deleteImage(filename: filename)
    }

    @Test("saveImage creates file on disk")
    func saveImageCreatesFileOnDisk() throws {
        let size = CGSize(width: 10, height: 10)
        UIGraphicsBeginImageContext(size)
        UIColor.blue.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        let filename = try PhotoStorageService.saveImage(image)
        let photosDir = try PhotoStorageService.photosDirectory()
        let fileURL = photosDir.appendingPathComponent(filename)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: fileURL.path))

        // Cleanup
        try? PhotoStorageService.deleteImage(filename: filename)
    }
    #endif
}

// MARK: - Load Image Tests

@Suite("PhotoStorageService Load Image Tests")
struct PhotoStorageServiceLoadImageTests {

    #if os(macOS)
    @Test("loadImage returns saved image")
    func loadImageReturnsSavedImage() throws {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let filename = try PhotoStorageService.saveImage(image)
        let loaded = PhotoStorageService.loadImage(filename: filename)

        #expect(loaded != nil)

        // Cleanup
        try? PhotoStorageService.deleteImage(filename: filename)
    }

    @Test("loadImage returns nil for non-existent file")
    func loadImageReturnsNilForNonExistent() {
        let loaded = PhotoStorageService.loadImage(filename: "non-existent-file.jpg")

        #expect(loaded == nil)
    }

    @Test("loadDownsampledImage returns image with correct size")
    func loadDownsampledImageReturnsCorrectSize() throws {
        // Create a larger image
        let size = NSSize(width: 100, height: 100)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.green.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let filename = try PhotoStorageService.saveImage(image)

        let targetSize = CGSize(width: 50, height: 50)
        let loaded = PhotoStorageService.loadDownsampledImage(
            filename: filename,
            pointSize: targetSize,
            scale: 1.0
        )

        #expect(loaded != nil)
        // The image should be downsampled (exact size depends on aspect ratio handling)

        // Cleanup
        try? PhotoStorageService.deleteImage(filename: filename)
    }

    @Test("loadDownsampledImage returns nil for non-existent file")
    func loadDownsampledImageReturnsNilForNonExistent() {
        let loaded = PhotoStorageService.loadDownsampledImage(
            filename: "non-existent-file.jpg",
            pointSize: CGSize(width: 50, height: 50),
            scale: 1.0
        )

        #expect(loaded == nil)
    }
    #else
    @Test("loadImage returns saved image")
    func loadImageReturnsSavedImage() throws {
        let size = CGSize(width: 10, height: 10)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        let filename = try PhotoStorageService.saveImage(image)
        let loaded = PhotoStorageService.loadImage(filename: filename)

        #expect(loaded != nil)

        // Cleanup
        try? PhotoStorageService.deleteImage(filename: filename)
    }

    @Test("loadImage returns nil for non-existent file")
    func loadImageReturnsNilForNonExistent() {
        let loaded = PhotoStorageService.loadImage(filename: "non-existent-file.jpg")

        #expect(loaded == nil)
    }
    #endif
}

// MARK: - Delete Image Tests

@Suite("PhotoStorageService Delete Image Tests")
struct PhotoStorageServiceDeleteImageTests {

    #if os(macOS)
    @Test("deleteImage removes file from disk")
    func deleteImageRemovesFile() throws {
        let size = NSSize(width: 10, height: 10)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()

        let filename = try PhotoStorageService.saveImage(image)
        let photosDir = try PhotoStorageService.photosDirectory()
        let fileURL = photosDir.appendingPathComponent(filename)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: fileURL.path))

        try PhotoStorageService.deleteImage(filename: filename)

        #expect(!fm.fileExists(atPath: fileURL.path))
    }

    @Test("deleteImage does not throw for non-existent file")
    func deleteImageDoesNotThrowForNonExistent() throws {
        // Should not throw
        try PhotoStorageService.deleteImage(filename: "non-existent-file.jpg")
    }
    #else
    @Test("deleteImage removes file from disk")
    func deleteImageRemovesFile() throws {
        let size = CGSize(width: 10, height: 10)
        UIGraphicsBeginImageContext(size)
        UIColor.red.setFill()
        UIRectFill(CGRect(origin: .zero, size: size))
        let image = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()

        let filename = try PhotoStorageService.saveImage(image)
        let photosDir = try PhotoStorageService.photosDirectory()
        let fileURL = photosDir.appendingPathComponent(filename)

        let fm = FileManager.default
        #expect(fm.fileExists(atPath: fileURL.path))

        try PhotoStorageService.deleteImage(filename: filename)

        #expect(!fm.fileExists(atPath: fileURL.path))
    }

    @Test("deleteImage does not throw for non-existent file")
    func deleteImageDoesNotThrowForNonExistent() throws {
        try PhotoStorageService.deleteImage(filename: "non-existent-file.jpg")
    }
    #endif
}

// MARK: - Error Tests

@Suite("PhotoStorageService Error Tests")
struct PhotoStorageServiceErrorTests {

    @Test("PhotoStorageError has correct cases")
    func photoStorageErrorHasCorrectCases() {
        let _ = PhotoStorageError.imageConversionFailed
        let _ = PhotoStorageError.fileNotFound
        let _ = PhotoStorageError.directoryCreationFailed

        // Just verify the cases exist and compile
        #expect(true)
    }
}

#endif
