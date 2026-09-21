import Foundation
@preconcurrency import PDFKit
import OSLog

/// Generates thumbnail images from PDF files for resource cards.
enum ResourceThumbnailGenerator {
    private static let logger = Logger.resources
    private static let thumbnailSize = CGSize(width: 200, height: 260)

    /// Generates a JPEG thumbnail of the first page of a PDF.
    /// Returns nil if generation fails.
    static func generateThumbnail(from url: URL) -> Data? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else {
            logger.warning("Failed to load PDF for thumbnail: \(url.lastPathComponent)")
            return nil
        }
        return PDFThumbnailRenderer.thumbnailData(from: page, fitting: thumbnailSize)
    }

    /// Generates a JPEG thumbnail from PDF data.
    static func generateThumbnail(from data: Data) -> Data? {
        PDFThumbnailRenderer.thumbnailData(from: data, fitting: thumbnailSize)
    }
}
