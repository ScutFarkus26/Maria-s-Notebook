import CoreGraphics
import CoreText
import Foundation
import PDFKit
@testable import CosmicDaybook
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Album PDFs made in code, and the small helpers the album suites share.
/// Nothing here reads the guide's own album PDFs: every file is written to a
/// fresh temporary directory that the test removes.
enum AlbumTestSupport {

    /// One outline entry: a lesson title, the page it starts on, and any
    /// entries nested under it.
    struct OutlineEntry {
        let title: String
        let page: Int
        var children: [OutlineEntry] = []
    }

    /// A fresh directory for one test's PDFs.
    static func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AlbumTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes a US-letter album of `pageCount` pages to `dir/fileName`. Every
    /// page has a coloured block and a line of text naming the page and
    /// `phrase` (so Find has something to match on each page), and the file
    /// carries `outline` as its table of contents.
    static func writeAlbum(named fileName: String, in dir: URL, pageCount: Int = 4,
                           outline: [OutlineEntry], phrase: String = "Stamp Game Division") throws -> URL {
        let draft = dir.appendingPathComponent("draft-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(draft as CFURL, mediaBox: &mediaBox, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let font = CTFontCreateWithName("Helvetica" as CFString, 22, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true
        ]
        for index in 0..<pageCount {
            context.beginPDFPage(nil)
            let hue = CGFloat(index % 5) / 5
            context.setFillColor(CGColor(red: 0.2 + hue * 0.6, green: 0.45, blue: 0.85 - hue * 0.5, alpha: 1))
            context.fill(CGRect(x: 60, y: 480, width: 360, height: 220))
            context.setFillColor(CGColor(red: 0.95, green: 0.7, blue: 0.1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 380, y: 300, width: 160, height: 120))
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            let text = NSAttributedString(string: "Page \(index + 1): \(phrase) with the skittles",
                                          attributes: attributes)
            context.textPosition = CGPoint(x: 60, y: 400)
            CTLineDraw(CTLineCreateWithAttributedString(text as CFAttributedString), context)
            context.endPDFPage()
        }
        context.closePDF()
        defer { try? FileManager.default.removeItem(at: draft) }

        let url = dir.appendingPathComponent(fileName)
        try autoreleasepool {
            guard let document = PDFDocument(url: draft) else { throw CocoaError(.fileReadCorruptFile) }
            let root = PDFOutline()
            for entry in outline {
                root.insertChild(makeOutlineItem(entry, in: document), at: root.numberOfChildren)
            }
            document.outlineRoot = root
            guard document.write(to: url) else { throw CocoaError(.fileWriteUnknown) }
        }
        return url
    }

    private static func makeOutlineItem(_ entry: OutlineEntry, in document: PDFDocument) -> PDFOutline {
        let item = PDFOutline()
        item.label = entry.title
        if let page = document.page(at: entry.page) {
            item.destination = PDFDestination(page: page, at: CGPoint(x: 0, y: 792))
        }
        for child in entry.children {
            item.insertChild(makeOutlineItem(child, in: document), at: item.numberOfChildren)
        }
        return item
    }

    /// A small album with a nested outline, the shape the real albums have.
    static let sampleOutline: [OutlineEntry] = [
        OutlineEntry(title: "Simple Operations", page: 0, children: [
            OutlineEntry(title: "Subtraction", page: 1)
        ]),
        OutlineEntry(title: "Stamp Game Division", page: 2),
        OutlineEntry(title: "Sharing Among the Skittles", page: 3)
    ]

    // MARK: Pixels

    /// The bitmap behind a platform image, at its own pixel size.
    static func bitmap(of image: PlatformImage) -> CGImage? {
        #if os(macOS)
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        return image.cgImage
        #endif
    }

    /// The image drawn into 8-bit sRGB RGBA at its pixel size, so two images
    /// compare by what they show rather than by how their bytes are laid out.
    static func rgba(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        pixels.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                    bitsPerComponent: 8, bytesPerRow: width * 4, space: sRGB,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.interpolationQuality = .none
            context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return pixels
    }

    // MARK: Waiting

    /// Polls until `condition` holds, so a passing run never waits out the
    /// timeout. Returns whether it held.
    static func waitUntil(timeout: Duration = .seconds(30),
                          _ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

/// Watches an object without keeping it alive.
final class AlbumTestWeakBox<Object: AnyObject> {
    weak var object: Object?
    init(_ object: Object?) { self.object = object }
}
