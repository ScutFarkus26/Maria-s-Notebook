import Foundation
@preconcurrency import PDFKit
import CoreData
import OSLog

/// Validates a PDF and inserts a `CDBookClubPacket` with thumbnail.
@MainActor
enum BookClubImportService {
    private static let logger = Logger.bookClub

    enum ImportRejection: LocalizedError {
        case fileMissing
        case notAPDF
        case encrypted
        case copyFailed(message: String)
        case unreadablePDF

        var errorDescription: String? {
            switch self {
            case .fileMissing: return "Couldn't find the PDF file."
            case .notAPDF: return "Only PDF files can be added as book club packets."
            case .encrypted: return "This PDF is password-protected and can't be imported."
            case .copyFailed(let message): return "Couldn't copy the PDF: \(message)"
            case .unreadablePDF: return "This PDF couldn't be opened."
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
                throw ImportRejection.copyFailed(message: underlying.localizedDescription)
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
            throw ImportRejection.copyFailed(message: error.localizedDescription)
        }

        return packet
    }
}
