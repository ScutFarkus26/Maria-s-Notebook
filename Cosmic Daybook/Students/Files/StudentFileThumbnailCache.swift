// StudentFileThumbnailCache.swift
// First-page thumbnails for the Student Files grid, cached on disk by file identity.

import CoreGraphics
import CryptoKit
import Foundation
import OSLog
@preconcurrency import PDFKit

/// First-page thumbnails for the Student Files grid. They are rendered off the main
/// thread by `PDFThumbnailRenderer`, the renderer Resources and Stories use, and
/// kept as JPEG in `Caches/StudentFileThumbnails` under the PDF's identity: its
/// path, modification date and size, or for a PDF still stored in its record, the
/// record and its byte count. A card never keeps a `PDFDocument` or `PDFView`
/// alive, and a PDF is opened once per version instead of on every visit.
nonisolated enum StudentFileThumbnailCache {
    private static let logger = Logger.students

    /// The box the first page is fitted into, in points. The card shows it at most
    /// 120 pt tall.
    static let fittingSize = CGSize(width: 240, height: 120)

    /// A rendered first page.
    nonisolated struct Thumbnail: Sendable, Equatable {
        /// The PDF's identity and the display scale; the thumbnail's
        /// `CachedThumbnail` key.
        let key: String
        /// JPEG from `PDFThumbnailRenderer`.
        let jpegData: Data
    }

    /// The thumbnail for a document stored at `url`, or else kept in `data` (a PDF
    /// still stored in its record, which `recordKey` names). Nil when there is no
    /// PDF or it has no first page. `directory` replaces the standard cache folder.
    @concurrent
    static func thumbnail(
        url: URL?,
        data: Data?,
        recordKey: String,
        scale: CGFloat,
        directory: URL? = nil
    ) async -> Thumbnail? {
        guard let identity = identity(url: url, data: data, recordKey: recordKey) else { return nil }
        let key = "\(identity)@\(scale)x"
        let cacheFile = (directory ?? standardDirectory)?.appendingPathComponent(fileName(for: key))
        if let cacheFile, let cached = try? Data(contentsOf: cacheFile), !cached.isEmpty {
            return Thumbnail(key: key, jpegData: cached)
        }
        guard let rendered = renderFirstPage(url: url, data: data, scale: scale) else { return nil }
        if let cacheFile {
            do {
                try rendered.write(to: cacheFile, options: .atomic)
            } catch {
                logger.error("Failed to cache a thumbnail: \(error.localizedDescription, privacy: .public)")
            }
        }
        return Thumbnail(key: key, jpegData: rendered)
    }

    /// What identifies the PDF's content: a file's path with its modification date
    /// and size, so a new version gets a new thumbnail; a PDF kept in its record,
    /// the record and the byte count, the way `CachedThumbnail` keys Resources and
    /// Stories. Nil when there is neither.
    static func identity(url: URL?, data: Data?, recordKey: String) -> String? {
        if let url {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0
            let size = attributes?[.size] as? Int ?? 0
            return "\(url.standardizedFileURL.path)|\(modified)|\(size)"
        }
        if let data, !data.isEmpty {
            return "\(recordKey)|\(data.count)"
        }
        return nil
    }

    /// `fittingSize` in the renderer's units. `UIGraphicsImageRenderer` already
    /// draws at the screen's scale; the Mac renderer draws one pixel per point, so
    /// there the box is scaled up to stay sharp on a Retina display.
    static func renderSize(scale: CGFloat) -> CGSize {
        #if os(macOS)
        return CGSize(width: fittingSize.width * scale, height: fittingSize.height * scale)
        #else
        return fittingSize
        #endif
    }

    /// Opens the PDF just long enough to draw its first page. Prefers `url`, as the
    /// `PDFView` thumbnail did, and uses `data` only when there is no file.
    private static func renderFirstPage(url: URL?, data: Data?, scale: CGFloat) -> Data? {
        #if DEBUG
        dispatchPrecondition(condition: .notOnQueue(.main))
        #endif
        let document: PDFDocument?
        if let url {
            document = PDFDocument(url: url)
        } else if let data {
            document = PDFDocument(data: data)
        } else {
            document = nil
        }
        guard let document, let page = document.page(at: 0) else { return nil }
        // A page only weakly references its document, which must outlive the drawing.
        return withExtendedLifetime(document) {
            PDFThumbnailRenderer.thumbnailData(from: page, fitting: renderSize(scale: scale))
        }
    }

    /// `Caches/StudentFileThumbnails`, created when missing.
    private static var standardDirectory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let directory = caches.appendingPathComponent("StudentFileThumbnails", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.error("Failed to create the thumbnail cache: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        return directory
    }

    /// A file name for `key`, which holds a full path: its SHA-256 in hex.
    private static func fileName(for key: String) -> String {
        SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined() + ".jpg"
    }
}
