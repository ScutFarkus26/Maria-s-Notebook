import Foundation
@preconcurrency import PDFKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Renders a JPEG (quality 0.7, white background) of a PDF page scaled to fit a
/// target size while keeping the page's aspect ratio. `BookClubThumbnailGenerator`,
/// `StoryThumbnailGenerator` and `ResourceThumbnailGenerator` forward here; they
/// differ only in target size and logger.
enum PDFThumbnailRenderer {
    /// First page of the PDF at `url`, or `nil` when it can't be opened or rendered.
    static func thumbnailData(from url: URL, fitting size: CGSize) -> Data? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else { return nil }
        return thumbnailData(from: page, fitting: size)
    }

    /// First page of the PDF in `data`, or `nil` when it can't be opened or rendered.
    static func thumbnailData(from data: Data, fitting size: CGSize) -> Data? {
        guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
        return thumbnailData(from: page, fitting: size)
    }

    static func thumbnailData(from page: PDFPage, fitting size: CGSize) -> Data? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale = Swift.min(
            size.width / pageRect.width,
            size.height / pageRect.height
        )
        let scaledSize = CGSize(
            width: pageRect.width * scale,
            height: pageRect.height * scale
        )

        #if os(macOS)
        return renderPageMacOS(page, size: scaledSize)
        #else
        return renderPageiOS(page, size: scaledSize)
        #endif
    }

    #if os(macOS)
    private static func renderPageMacOS(_ page: PDFPage, size: CGSize) -> Data? {
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.setFillColor(NSColor.white.cgColor)
            context.fill(rect)

            let pageRect = page.bounds(for: .mediaBox)
            let scaleX = size.width / pageRect.width
            let scaleY = size.height / pageRect.height
            context.scaleBy(x: scaleX, y: scaleY)
            page.draw(with: .mediaBox, to: context)
            return true
        }

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        return jpeg
    }
    #else
    private static func renderPageiOS(_ page: PDFPage, size: CGSize) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))

            let context = ctx.cgContext
            let pageRect = page.bounds(for: .mediaBox)
            let scaleX = size.width / pageRect.width
            let scaleY = size.height / pageRect.height

            // PDFKit draws with a flipped coordinate system
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: scaleX, y: -scaleY)
            page.draw(with: .mediaBox, to: context)
        }
        return image.jpegData(compressionQuality: 0.7)
    }
    #endif
}
