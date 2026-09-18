import Foundation
@preconcurrency import PDFKit
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Generates thumbnail images from PDF files for resource cards.
enum ResourceThumbnailGenerator {
    private static let logger = Logger.resources
    private static let thumbnailSize = CGSize(width: 200, height: 260)

    /// Generates a JPEG thumbnail of the first page of a PDF.
    /// Returns nil if generation fails.
    static func generateThumbnail(from url: URL) -> Data? {
        guard let document = PDFDocument(url: url),
              let page = document.page(at: 0) else {
            logger.warning("Failed to load PDF for thumbnail: \(url.lastPathComponent)")
            return nil
        }

        return renderPage(page)
    }

    /// Generates a JPEG thumbnail from PDF data.
    static func generateThumbnail(from data: Data) -> Data? {
        guard let document = PDFDocument(data: data),
              let page = document.page(at: 0) else {
            return nil
        }

        return renderPage(page)
    }

    private static func renderPage(_ page: PDFPage) -> Data? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale = min(
            thumbnailSize.width / pageRect.width,
            thumbnailSize.height / pageRect.height
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

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
            return nil
        }
        return jpegData
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
