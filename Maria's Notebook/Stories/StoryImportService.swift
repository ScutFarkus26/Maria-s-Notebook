import Foundation
@preconcurrency import PDFKit
import CoreData
import OSLog

/// Coordinates the end-to-end flow of importing a PDF as a story:
/// validate → copy → insert entity → generate thumbnail → enqueue analysis.
@MainActor
enum StoryImportService {
    private static let logger = Logger.stories

    /// Errors surfaced to the user when an import is rejected.
    enum ImportRejection: LocalizedError {
        case fileMissing
        case notAPDF
        case encrypted
        case copyFailed(message: String)
        case unreadablePDF

        var errorDescription: String? {
            switch self {
            case .fileMissing: return "Couldn't find the PDF file."
            case .notAPDF: return "Only PDF files can be added as stories."
            case .encrypted: return "This PDF is password-protected and can't be imported."
            case .copyFailed(let message): return "Couldn't copy the PDF: \(message)"
            case .unreadablePDF: return "This PDF couldn't be opened."
            }
        }
    }

    /// Imports a single PDF and kicks off background analysis.
    /// Returns the freshly-inserted (and saved) `CDStory`.
    @discardableResult
    static func importPDF(
        at sourceURL: URL,
        context: NSManagedObjectContext
    ) throws -> CDStory {
        // Validate format up front.
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

        // Copy file into managed storage.
        let storyID = UUID()
        let proposedTitle = sourceURL.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let imported: StoryFileStorage.ImportedStoryFile
        do {
            imported = try StoryFileStorage.importPDF(
                from: sourceURL,
                storyID: storyID,
                title: proposedTitle.isEmpty ? nil : proposedTitle
            )
        } catch let error as StoryFileStorage.StoryFileError {
            switch error {
            case .sourceMissing: throw ImportRejection.fileMissing
            case .notAPDF: throw ImportRejection.notAPDF
            case .encrypted: throw ImportRejection.encrypted
            case .copyFailed(let underlying):
                throw ImportRejection.copyFailed(message: underlying.localizedDescription)
            }
        }

        // Insert entity.
        let story = CDStory(context: context)
        story.id = storyID
        story.title = proposedTitle
        story.pdfFileBookmark = imported.bookmark
        story.pdfFileRelativePath = imported.relativePath
        story.pageCount = Int32(document.pageCount)
        story.analysisStatus = StoryAnalyzer.isAIEnabled ? .analyzing : .manual

        // Synchronous thumbnail of page 1 (cheap).
        if let thumbnail = StoryThumbnailGenerator.generateThumbnail(from: imported.url) {
            story.thumbnailData = thumbnail
        }

        // Synchronously extract text + hash so the entity persists those even if the
        // app quits before analysis runs.
        let extracted = StoryAnalyzer.extractText(from: imported.url)
        if let extracted {
            story.extractedTextHash = extracted.hash
            if !StoryAnalyzer.hasUsableText(extracted.text) {
                story.analysisStatus = .manual
                story.analysisErrorMessage = "Couldn't read text from this PDF — add details manually."
            }
        }

        story.modifiedAt = Date()

        do {
            try context.save()
        } catch {
            logger.error("Failed to save story after import: \(error.localizedDescription, privacy: .public)")
            // Roll back the file on save failure to avoid orphaning.
            try? StoryFileStorage.deleteIfManaged(imported.url)
            context.delete(story)
            throw ImportRejection.copyFailed(message: error.localizedDescription)
        }

        // Kick off async analysis if we have usable text and AI is on.
        if story.analysisStatus == .analyzing,
           let text = extracted?.text,
           StoryAnalyzer.hasUsableText(text) {
            scheduleAnalysis(for: story.objectID, extractedText: text, context: context)
        }

        return story
    }

    /// Re-runs analysis for an existing story. Skips overwriting fields the user has
    /// edited manually.
    static func reanalyze(
        story: CDStory,
        context: NSManagedObjectContext
    ) {
        guard let url = StoryFileStorage.resolveURL(
            bookmark: story.pdfFileBookmark,
            relativePath: story.pdfFileRelativePath
        ) else {
            story.analysisStatus = .failed
            story.analysisErrorMessage = "PDF file is missing."
            _ = context.safeSave()
            return
        }

        guard let extracted = StoryAnalyzer.extractText(from: url) else {
            story.analysisStatus = .failed
            story.analysisErrorMessage = "Couldn't read this PDF."
            _ = context.safeSave()
            return
        }

        story.extractedTextHash = extracted.hash
        story.analysisStatus = .analyzing
        story.analysisErrorMessage = ""
        _ = context.safeSave()

        scheduleAnalysis(for: story.objectID, extractedText: extracted.text, context: context)
    }

    // MARK: - Background analysis

    private static func scheduleAnalysis(
        for objectID: NSManagedObjectID,
        extractedText: String,
        context: NSManagedObjectContext
    ) {
        StoryImportQueue.shared.submit { [extractedText] in
            do {
                let result = try await StoryAnalyzer.analyze(text: extractedText)
                await applyResult(result, to: objectID, context: context)
            } catch {
                await applyFailure(error, to: objectID, context: context)
            }
        }
    }

    private static func applyResult(
        _ result: StoryAnalysisResult,
        to objectID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) async {
        await context.perform {
            guard let story = try? context.existingObject(with: objectID) as? CDStory else { return }
            if !story.userEditedTitle, !result.title.isEmpty {
                story.title = result.title
            }
            if !story.userEditedThemes {
                story.themesArray = result.themes
            }
            if story.gradeMin == nil {
                story.gradeMin = result.gradeMin
            }
            if story.gradeMax == nil {
                story.gradeMax = result.gradeMax
            }
            if story.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                story.summary = result.summary
            }
            story.analysisModelVersion = result.modelVersion
            story.analysisStatus = .complete
            story.analysisErrorMessage = ""
            story.modifiedAt = Date()
            _ = context.safeSave()
        }
    }

    private static func applyFailure(
        _ error: Error,
        to objectID: NSManagedObjectID,
        context: NSManagedObjectContext
    ) async {
        await context.perform {
            guard let story = try? context.existingObject(with: objectID) as? CDStory else { return }
            if let analyzerError = error as? StoryAnalyzerError {
                switch analyzerError {
                case .aiUnavailable:
                    story.analysisStatus = .manual
                case .insufficientText:
                    story.analysisStatus = .manual
                    story.analysisErrorMessage = "Couldn't read text from this PDF — add details manually."
                case .timedOut:
                    story.analysisStatus = .failed
                    story.analysisErrorMessage = "Analysis timed out. Try again."
                case .generationFailed(let message):
                    story.analysisStatus = .failed
                    story.analysisErrorMessage = message
                }
            } else {
                story.analysisStatus = .failed
                story.analysisErrorMessage = error.localizedDescription
            }
            story.modifiedAt = Date()
            _ = context.safeSave()
        }
    }
}
