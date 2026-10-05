import Foundation
import UIKit
import Testing
@testable import Daybook_Assistant

// Classroom → Background: what's stored, the seasons, the frosted tiles, and
// her photo on disk.
@Suite("Assistant backgrounds")
@MainActor
struct AssistantWallpaperTests {

    @Test("A stored background comes back as itself; anything unknown is Sky")
    func resolvesStoredNames() {
        for wallpaper in AssistantWallpaper.allCases {
            #expect(AssistantWallpaper.resolved(wallpaper.rawValue, photoExists: true) == wallpaper)
        }
        #expect(AssistantWallpaper.resolved("aurora", photoExists: true) == .sky)
        #expect(AssistantWallpaper.resolved(nil, photoExists: true) == .sky)
    }

    @Test("Photo with no photo saved is Sky")
    func photoWithoutFile() {
        #expect(AssistantWallpaper.resolved("photo", photoExists: false) == .sky)
    }

    @Test("Only Sky and Plain leave the tiles unfrosted")
    func quietBackgrounds() {
        #expect(AssistantWallpaper.allCases.filter(\.isQuiet) == [.sky, .plain])
    }

    @Test("Tiles keep their card on Sky or Plain and frost over a picture")
    func tileBases() {
        #expect(TileBase(status: .unmarked, quietBackdrop: true) == .card)
        #expect(TileBase(status: .present, quietBackdrop: true) == .card)
        #expect(TileBase(status: .absent, quietBackdrop: true) == .clear)
        #expect(TileBase(status: .unmarked, quietBackdrop: false) == .frosted)
        #expect(TileBase(status: .absent, quietBackdrop: false) == .thinFrost)
    }

    @Test("Seasons follow the day on screen")
    func seasons() throws {
        func season(_ iso: String) throws -> AssistantWallpaper.Season {
            AssistantWallpaper.season(for: try AssistantTestSupport.day(iso))
        }
        #expect(try season("2026-09-01") == .autumn)
        #expect(try season("2026-11-30") == .autumn)
        #expect(try season("2026-12-01") == .winter)
        #expect(try season("2027-02-28") == .winter)
        #expect(try season("2027-03-01") == .spring)
        #expect(try season("2027-05-31") == .spring)
        #expect(try season("2027-06-01") == .summer)
        #expect(try season("2027-08-31") == .summer)
    }

    @Test("A picked photo is saved small, and Remove deletes it")
    func photoSaveAndRemove() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "WallpaperTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = AssistantWallpaperPhoto(directory: directory)
        #expect(!photo.hasPhoto)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: 3000, height: 2000), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 3000, height: 1000))
            UIColor.systemPink.setFill()
            context.fill(CGRect(x: 0, y: 1000, width: 3000, height: 1000))
        }
        try await photo.save(try #require(big.pngData()))

        #expect(photo.hasPhoto)
        let saved = try #require(photo.image)
        let longSide = max(saved.size.width, saved.size.height) * saved.scale
        #expect(longSide <= CGFloat(AssistantWallpaperPhoto.longSide))
        #expect(longSide >= CGFloat(AssistantWallpaperPhoto.longSide) - 1)

        photo.remove()
        #expect(!photo.hasPhoto)
        #expect(photo.image == nil)
    }

    @Test("A first read that finds no photo is tried again, and finds it once it's there")
    func failedReadRetried() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "WallpaperTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let photo = AssistantWallpaperPhoto(directory: directory)
        photo.loadIfNeeded()
        #expect(photo.image == nil)

        // The file becomes readable later (as after the first unlock).
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let small = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #require(small.jpegData(compressionQuality: 0.8)).write(to: photo.fileURL)

        photo.loadIfNeeded()
        #expect(photo.image != nil)
    }

    @Test("Data that isn't an image is refused")
    func unreadablePhoto() async {
        await #expect(throws: AssistantWallpaperPhoto.ImportError.self) {
            _ = try await AssistantWallpaperPhoto.prepare(Data("not a photo".utf8))
        }
    }
}
