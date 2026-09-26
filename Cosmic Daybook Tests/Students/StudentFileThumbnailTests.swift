import CoreGraphics
import Foundation
@preconcurrency import PDFKit
import Testing
@testable import CosmicDaybook

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The Student Files grid's first-page thumbnails: rendered off the main thread by
/// the shared `PDFThumbnailRenderer`, cached by file identity, and shown through
/// `CachedThumbnail` instead of a live `PDFView` per card.
@Suite("Student file thumbnails")
struct StudentFileThumbnailTests {

    /// A one-page PDF of `size` points: a red top-left quadrant on a grey `shade`.
    static func makePDF(size: CGSize = CGSize(width: 612, height: 792), shade: CGFloat = 0.5) -> Data {
        let output = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: size)
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: shade, alpha: 1))
        context.fill(mediaBox)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: size.height / 2, width: size.width / 2, height: size.height / 2))
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }

    /// Pixels per point `PDFThumbnailRenderer` draws at on this platform.
    static var rendererScale: CGFloat {
        #if os(macOS)
        return 1
        #else
        return UIGraphicsImageRendererFormat.preferred().scale
        #endif
    }

    @Test("Fifteen PDFs each get a cached first-page thumbnail, rendered off the main thread")
    func fifteenPDFs() async throws {
        let pdfDirectory = try TestImages.scratchDirectory()
        let cacheDirectory = try TestImages.scratchDirectory()
        defer {
            try? FileManager.default.removeItem(at: pdfDirectory)
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
        let expectedHeight = Int((StudentFileThumbnailCache.renderSize(scale: 2).height * Self.rendererScale).rounded())
        var keys: Set<String> = []

        for index in 0..<15 {
            let url = pdfDirectory.appendingPathComponent("Document \(index).pdf")
            try Self.makePDF(shade: CGFloat(index) / 15).write(to: url)

            // The render step traps on the main thread in Debug, and this test runs on
            // the main actor: a thumbnail at all means it was drawn elsewhere.
            let made = await StudentFileThumbnailCache.thumbnail(
                url: url, data: nil, recordKey: "", scale: 2, directory: cacheDirectory
            )
            let thumbnail = try #require(made)
            keys.insert(thumbnail.key)

            let page = try #require(TestImages.stored(thumbnail.jpegData))
            // A letter page fitted into the 120-pt-tall box, right way up.
            #expect(page.height == expectedHeight)
            #expect(abs(Double(page.width) / Double(page.height) - 612.0 / 792.0) < 0.02)
            #expect(TestImages.color(in: page, x: 0.1, y: 0.1) == "red")
            #expect(CachedThumbnail.image(from: thumbnail.jpegData, cacheKey: thumbnail.key) != nil)
            ImageCache.shared.removeObject(forKey: "\(thumbnail.key)#\(thumbnail.jpegData.count)" as NSString)
        }

        #expect(keys.count == 15)
        #expect(try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path).count == 15)
    }

    @Test("A thumbnail comes from the cache until its PDF changes")
    func cachedUntilThePDFChanges() async throws {
        let pdfDirectory = try TestImages.scratchDirectory()
        let cacheDirectory = try TestImages.scratchDirectory()
        defer {
            try? FileManager.default.removeItem(at: pdfDirectory)
            try? FileManager.default.removeItem(at: cacheDirectory)
        }
        let url = pdfDirectory.appendingPathComponent("Report.pdf")
        let original = Self.makePDF(shade: 0.2)
        try original.write(to: url)
        // A whole-second date, so setting it again later restores it exactly.
        let modified = Date(timeIntervalSinceReferenceDate: 800_000_000)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        let first = await StudentFileThumbnailCache.thumbnail(
            url: url, data: nil, recordKey: "", scale: 2, directory: cacheDirectory
        )
        let firstThumbnail = try #require(first)

        // Same size and modification date, but no longer a PDF: a render would fail,
        // so getting the thumbnail back means the cache answered.
        try Data(repeating: 0x20, count: original.count).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
        let again = await StudentFileThumbnailCache.thumbnail(
            url: url, data: nil, recordKey: "", scale: 2, directory: cacheDirectory
        )
        #expect(again == firstThumbnail)

        // A new version of the file is drawn afresh.
        try Self.makePDF(size: CGSize(width: 792, height: 612), shade: 0.8).write(to: url)
        let later = modified.addingTimeInterval(60)
        try FileManager.default.setAttributes([.modificationDate: later], ofItemAtPath: url.path)
        let changed = await StudentFileThumbnailCache.thumbnail(
            url: url, data: nil, recordKey: "", scale: 2, directory: cacheDirectory
        )
        let changedThumbnail = try #require(changed)
        #expect(changedThumbnail.key != firstThumbnail.key)
        let page = try #require(TestImages.stored(changedThumbnail.jpegData))
        #expect(page.width > page.height)
    }

    @Test("A PDF still stored in its record is keyed by the record; no PDF, no thumbnail")
    func pdfKeptInTheRecord() async throws {
        let cacheDirectory = try TestImages.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: cacheDirectory) }
        let pdf = Self.makePDF()
        let recordKey = "x-coredata://TEST/Document/p1"

        let made = await StudentFileThumbnailCache.thumbnail(
            url: nil, data: pdf, recordKey: recordKey, scale: 2, directory: cacheDirectory
        )
        let thumbnail = try #require(made)
        #expect(thumbnail.key.hasPrefix("\(recordKey)|\(pdf.count)"))

        let none = await StudentFileThumbnailCache.thumbnail(
            url: nil, data: nil, recordKey: recordKey, scale: 2, directory: cacheDirectory
        )
        #expect(none == nil)
    }

    @Test("The shared renderer draws the same thumbnail off the main thread as on it")
    func rendererMatchesOnAndOffTheMainThread() async throws {
        let pdf = Self.makePDF()
        let size = StudentFileThumbnailCache.renderSize(scale: 2)
        let document = try #require(PDFDocument(data: pdf))
        let page = try #require(document.page(at: 0))
        let onMain = try #require(PDFThumbnailRenderer.thumbnailData(from: page, fitting: size))

        let rendered = await Task.detached { () -> Data? in
            guard let document = PDFDocument(data: pdf), let page = document.page(at: 0) else { return nil }
            return withExtendedLifetime(document) {
                PDFThumbnailRenderer.thumbnailData(from: page, fitting: size)
            }
        }.value
        let offMain = try #require(rendered)

        let mainPixels = try #require(TestImages.stored(onMain))
        let offMainPixels = try #require(TestImages.stored(offMain))
        #expect(offMainPixels.width == mainPixels.width)
        #expect(offMainPixels.height == mainPixels.height)
        #expect(TestImages.rgba(offMainPixels) == TestImages.rgba(mainPixels))
    }
}
