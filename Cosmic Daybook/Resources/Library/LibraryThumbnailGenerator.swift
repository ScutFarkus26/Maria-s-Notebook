import Foundation
@preconcurrency import PDFKit
import OSLog

/// Renders the JPEG thumbnail of a PDF's first page that the Resources
/// screen's cards show, for stories, book club packets and resource files alike.
enum LibraryThumbnailGenerator {
    private static let logger = Logger.resources
    private static let thumbnailSize = CGSize(width: 240, height: 320)

    /// The first page's thumbnail, or nil when the file isn't a PDF that opens.
    static func generateThumbnail(from url: URL) -> Data? {
        guard let page = PDFDocument(url: url)?.page(at: 0) else {
            logger.warning("Couldn't open a PDF for its thumbnail: \(url.lastPathComponent, privacy: .public)")
            return nil
        }
        return PDFThumbnailRenderer.thumbnailData(from: page, fitting: thumbnailSize)
    }
}
