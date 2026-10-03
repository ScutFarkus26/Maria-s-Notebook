import Foundation
@preconcurrency import PDFKit
import CoreData
import OSLog

/// Validates a PDF and inserts a `CDBookClubPacket` with thumbnail.
enum BookClubImportService {
    private static let logger = Logger.bookClub

    enum ImportRejection: LocalizedError {
        case fileMissing
        case notAPDF
        case encrypted
        /// Copying the PDF in failed; the file error is translated, never shown raw.
        case copyFailed(underlying: Error)
        /// The PDF was copied but the new packet couldn't be saved.
        case saveFailed
        case unreadablePDF

        var errorDescription: String? {
            switch self {
            case .fileMissing: return "Couldn't find that PDF. It may have been moved or deleted."
            case .notAPDF: return "Only PDF files can be added as book club packets."
            case .encrypted: return "This PDF is locked with a password and can't be added."
            case .copyFailed(let underlying):
                return ManagedPDFFileStorage.ImportError.copyFailureMessage(for: underlying)
            case .saveFailed: return "Couldn't save the new packet. Try again."
            case .unreadablePDF: return "This PDF couldn't be opened. It may be damaged."
            }
        }
    }

    @discardableResult
    static func importPDF(
        at sourceURL: URL,
        context: NSManagedObjectContext
    ) throws -> CDBookClubPacket {
        let ext = sourceURL.pathExtension.lowercased()
        guard ext == "pdf" else { throw ImportRejection.notAPDF }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ImportRejection.fileMissing
        }
        guard let document = PDFDocument(url: sourceURL) else {
            throw ImportRejection.unreadablePDF
        }
        if document.isEncrypted || document.isLocked {
            throw ImportRejection.encrypted
        }

        let packetID = UUID()
        let proposedTitle = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let imported: BookClubFileStorage.ImportedPacketFile
        do {
            imported = try BookClubFileStorage.importPDF(
                from: sourceURL,
                packetID: packetID,
                title: proposedTitle.isEmpty ? nil : proposedTitle
            )
        } catch let error as BookClubFileStorage.BookClubFileError {
            switch error {
            case .sourceMissing: throw ImportRejection.fileMissing
            case .notAPDF: throw ImportRejection.notAPDF
            case .encrypted: throw ImportRejection.encrypted
            case .copyFailed(let underlying):
                throw ImportRejection.copyFailed(underlying: underlying)
            }
        }

        let packet = CDBookClubPacket(context: context)
        packet.id = packetID
        packet.title = proposedTitle
        packet.packetPDFBookmark = imported.bookmark
        packet.packetPDFRelativePath = imported.relativePath
        packet.pageCount = Int32(document.pageCount)

        if let thumbnail = BookClubThumbnailGenerator.generateThumbnail(from: imported.url) {
            packet.thumbnailData = thumbnail
        }

        packet.modifiedAt = Date()

        do {
            try context.save()
        } catch {
            logger.error("Failed to save packet after import: \(error.localizedDescription, privacy: .public)")
            try? BookClubFileStorage.deleteIfManaged(imported.url)
            context.delete(packet)
            throw ImportRejection.saveFailed
        }

        return packet
    }
}
