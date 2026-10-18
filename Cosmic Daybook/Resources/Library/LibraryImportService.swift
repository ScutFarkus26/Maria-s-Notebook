import Foundation
@preconcurrency import PDFKit
import CoreData
import OSLog

/// Adds files to the Resources screen: a PDF as a story or as a book club
/// packet (validate → copy into its folder → insert → thumbnail → save, and for
/// a story, analysis), and any file as a resource. Replaces the near-identical
/// `StoryImportService` and `BookClubImportService`.
enum LibraryImportService {
    private static let logger = Logger.resources

    /// What a PDF is added as: decides the folder, the record and the words.
    nonisolated enum PDFKind: Sendable {
        case story
        case packet

        /// The plural noun the "only PDFs" message names.
        var pluralNoun: String {
            switch self {
            case .story: return "stories"
            case .packet: return "book club packets"
            }
        }

        /// The noun the "couldn't save" message names.
        var singularNoun: String {
            switch self {
            case .story: return "story"
            case .packet: return "packet"
            }
        }
    }

    /// Why an import was turned down, in plain words.
    nonisolated enum ImportRejection: LocalizedError, Equatable {
        case fileMissing
        case notAPDF(PDFKind)
        case encrypted
        /// Copying the PDF in failed; the file error is translated, never shown raw.
        case copyFailed(message: String)
        /// The PDF was copied but the new record couldn't be saved.
        case saveFailed(PDFKind)
        case unreadablePDF

        var errorDescription: String? {
            switch self {
            case .fileMissing: return "Couldn't find that PDF. It may have been moved or deleted."
            case .notAPDF(let kind): return "Only PDF files can be added as \(kind.pluralNoun)."
            case .encrypted: return "This PDF is locked with a password and can't be added."
            case .copyFailed(let message): return message
            case .saveFailed(let kind): return "Couldn't save the new \(kind.singularNoun). Try again."
            case .unreadablePDF: return "This PDF couldn't be opened. It may be damaged."
            }
        }

        static func == (lhs: ImportRejection, rhs: ImportRejection) -> Bool {
            lhs.errorDescription == rhs.errorDescription
        }
    }

    // MARK: - Stories and packets

    /// Imports a PDF as a story and starts its analysis when Apple
    /// Intelligence is on. Returns the saved story.
    @discardableResult
    static func importStory(
        at sourceURL: URL,
        context: NSManagedObjectContext,
        storage: ManagedPDFFileStorage = LibraryFileStorage.stories
    ) throws -> CDStory {
        let pdf = try copyPDF(at: sourceURL, as: .story, into: storage)

        let story = CDStory(context: context)
        story.id = pdf.id
        story.title = pdf.title
        story.pdfFileBookmark = pdf.file.bookmark
        story.pdfFileRelativePath = pdf.file.relativePath
        story.pageCount = Int32(pdf.document.pageCount)
        story.analysisStatus = StoryAnalyzer.isAIEnabled ? .analyzing : .manual
        story.thumbnailData = LibraryThumbnailGenerator.generateThumbnail(from: pdf.file.url)

        // Text and its hash are kept now, so the story has them even if the
        // app quits before analysis runs.
        let extracted = StoryAnalyzer.extractText(from: pdf.file.url)
        if let extracted {
            story.extractedTextHash = extracted.hash
            if !StoryAnalyzer.hasUsableText(extracted.text), !StoryAnalyzer.isVisualAnalysisEnabled {
                // No readable text and no vision-capable model to read the pages.
                story.analysisStatus = .manual
                story.analysisErrorMessage = "Couldn't read the words in this PDF. Add the details yourself."
            }
        }
        story.modifiedAt = Date()

        try save(story, kind: .story, file: pdf.file.url, storage: storage, context: context)
        StoryAnalysisRunner.scheduleInitialAnalysis(
            for: story, extractedText: extracted?.text, url: pdf.file.url, context: context
        )
        return story
    }

    /// Imports a PDF as a book club packet. Returns the saved packet.
    @discardableResult
    static func importPacket(
        at sourceURL: URL,
        context: NSManagedObjectContext,
        storage: ManagedPDFFileStorage = LibraryFileStorage.packets
    ) throws -> CDBookClubPacket {
        let pdf = try copyPDF(at: sourceURL, as: .packet, into: storage)

        let packet = CDBookClubPacket(context: context)
        packet.id = pdf.id
        packet.title = pdf.title
        packet.packetPDFBookmark = pdf.file.bookmark
        packet.packetPDFRelativePath = pdf.file.relativePath
        packet.pageCount = Int32(pdf.document.pageCount)
        packet.thumbnailData = LibraryThumbnailGenerator.generateThumbnail(from: pdf.file.url)
        packet.modifiedAt = Date()

        try save(packet, kind: .packet, file: pdf.file.url, storage: storage, context: context)
        return packet
    }

    /// The import's message for the alert: the rejection's plain sentence, or
    /// a general one for anything else (logged, never shown raw).
    static func message(for error: Error) -> String {
        if let rejection = error as? ImportRejection, let text = rejection.errorDescription {
            return text
        }
        logger.error("Import failed: \(error.localizedDescription, privacy: .public)")
        return AppErrorMessages.importMessage(for: error, fileType: "PDF")
    }

    /// A PDF checked and copied into its folder, with the title it proposes.
    private struct CopiedPDF {
        let id: UUID
        let title: String
        let document: PDFDocument
        let file: ManagedPDFFileStorage.ImportedFile
    }

    private static func copyPDF(
        at sourceURL: URL,
        as kind: PDFKind,
        into storage: ManagedPDFFileStorage
    ) throws -> CopiedPDF {
        guard sourceURL.pathExtension.lowercased() == "pdf" else { throw ImportRejection.notAPDF(kind) }
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw ImportRejection.fileMissing
        }
        guard let document = PDFDocument(url: sourceURL) else {
            throw ImportRejection.unreadablePDF
        }
        if document.isEncrypted || document.isLocked {
            throw ImportRejection.encrypted
        }

        let title = proposedTitle(for: sourceURL)
        do {
            let file = try storage.importPDF(
                from: sourceURL,
                title: title.isEmpty ? nil : title,
                subject: kind.pluralNoun
            )
            return CopiedPDF(id: UUID(), title: title, document: document, file: file)
        } catch let error as ManagedPDFFileStorage.ImportError {
            switch error {
            case .sourceMissing: throw ImportRejection.fileMissing
            case .notAPDF: throw ImportRejection.notAPDF(kind)
            case .encrypted: throw ImportRejection.encrypted
            case .copyFailed(let underlying):
                throw ImportRejection.copyFailed(
                    message: ManagedPDFFileStorage.ImportError.copyFailureMessage(for: underlying)
                )
            }
        }
    }

    /// "Pond_Life-Unit" → "Pond Life Unit".
    static func proposedTitle(for url: URL) -> String {
        url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Saves the new record; on failure removes it and its copied file so
    /// nothing is left orphaned.
    private static func save(
        _ object: NSManagedObject,
        kind: PDFKind,
        file: URL,
        storage: ManagedPDFFileStorage,
        context: NSManagedObjectContext
    ) throws {
        do {
            try context.save()
        } catch {
            let noun = kind.singularNoun
            let reason = error.localizedDescription
            logger.error("Couldn't save a new \(noun, privacy: .public): \(reason, privacy: .public)")
            try? storage.deleteIfManaged(file)
            context.delete(object)
            throw ImportRejection.saveFailed(kind)
        }
    }

    // MARK: - Resource files

    /// A file copied into the resource folder, with what the new resource records.
    struct ImportedResourceFile {
        let relativePath: String
        let bookmark: Data
        let fileSizeBytes: Int64
        let thumbnail: Data?
    }

    /// Copies any file into `Resource Files/<category>/` and reads what a
    /// resource stores about it. The caller makes the resource.
    static func importResourceFile(
        from sourceURL: URL,
        title: String,
        category: ResourceCategory,
        storage: ManagedPDFFileStorage = LibraryFileStorage.resources
    ) throws -> ImportedResourceFile {
        let (destURL, relativePath) = try LibraryFileStorage.importResourceFile(
            from: sourceURL, title: title, category: category, in: storage
        )
        let attributes = try FileManager.default.attributesOfItem(atPath: destURL.path)
        return ImportedResourceFile(
            relativePath: relativePath,
            bookmark: try storage.makeBookmark(for: destURL),
            fileSizeBytes: (attributes[.size] as? Int64) ?? 0,
            thumbnail: LibraryThumbnailGenerator.generateThumbnail(from: destURL)
        )
    }

    /// Adds a dropped PDF as a resource in Other, titled after the file.
    /// Returns the alert message when it fails, nil when it worked.
    static func importDroppedResource(
        at url: URL,
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator
    ) -> String? {
        let stem = url.deletingPathExtension().lastPathComponent.trimmed()
        let title = stem.isEmpty ? "Untitled Resource" : stem
        do {
            let file = try importResourceFile(from: url, title: title, category: .other)
            ResourceRepository(context: context).createResource(
                title: title,
                category: .other,
                fileBookmark: file.bookmark,
                fileRelativePath: file.relativePath,
                fileSizeBytes: file.fileSizeBytes,
                thumbnailData: file.thumbnail
            )
            saveCoordinator.save(context, reason: "Import dropped PDF")
            return nil
        } catch {
            logger.warning("Dropped PDF import failed: \(error.localizedDescription, privacy: .public)")
            return AppErrorMessages.importMessage(for: error, fileType: "PDF")
        }
    }
}
