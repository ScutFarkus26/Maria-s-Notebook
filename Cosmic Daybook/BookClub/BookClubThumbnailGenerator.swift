import Foundation
@preconcurrency import PDFKit
import OSLog

/// Renders a JPEG thumbnail of the first page of a book club packet PDF.
enum BookClubThumbnailGenerator {
    private static let logger = Logger.bookClub
    private static let thumbnailSize = CGSize(width: 240, height: 320)

    static func generateThumbnail(from url: URL) -> Data? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else {
            logger.warning("Failed to open PDF for thumbnail: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        return PDFThumbnailRenderer.thumbnailData(from: page, fitting: thumbnailSize)
    }
}
