import Foundation
@preconcurrency import PDFKit
import CoreData
import OSLog

/// Coordinates the end-to-end flow of importing a PDF as a story:
/// validate → copy → insert entity → generate thumbnail → enqueue analysis.
enum StoryImportService {
    private static let logger = Logger.stories

    /// Errors surfaced to the user when an import is rejected.
    enum ImportRejection: LocalizedError {
        case fileMissing
        case notAPDF
        case encrypted
        /// Copying the PDF into the story library failed; the file error is
        /// translated, never shown raw.
        case copyFailed(underlying: Error)
        /// The PDF was copied but the new story couldn't be saved.
        case saveFailed
        case unreadablePDF

        var errorDescription: String? {
            switch self {
            case .fileMissing: return "Couldn't find that PDF. It may have been moved or deleted."
            case .notAPDF: return "Only PDF files can be added as stories."
            case .encrypted: return "This PDF is locked with a password and can't be added."
            case .copyFailed(let underlying):
                return ManagedPDFFileStorage.ImportError.copyFailureMessage(for: underlying)
            case .saveFailed: return "Couldn't save the new story. Try again."
            case .unreadablePDF: return "This PDF couldn't be opened. It may be damaged."
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
                throw ImportRejection.copyFailed(underlying: underlying)
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
            if !StoryAnalyzer.hasUsableText(extracted.text), !StoryAnalyzer.isVisualAnalysisEnabled {
                // No readable text and no vision-capable model to read the pages.
                story.analysisStatus = .manual
                story.analysisErrorMessage = "Couldn't read the words in this PDF. Add the details yourself."
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
            throw ImportRejection.saveFailed
        }

        scheduleInitialAnalysis(
            for: story, extractedText: extracted?.text, url: imported.url, context: context
        )

        return story
    }

    /// Kicks off async analysis after import when AI is on: text analysis when the
    /// PDF has readable text, visual page analysis otherwise (scanned/picture books).
    private static func scheduleInitialAnalysis(
        for story: CDStory,
        extractedText: String?,
        url: URL,
        context: NSManagedObjectContext
    ) {
        guard story.analysisStatus == .analyzing else { return }
        if let text = extractedText, StoryAnalyzer.hasUsableText(text) {
            scheduleAnalysis(for: story.objectID, input: .text(text), context: context)
        } else if StoryAnalyzer.isVisualAnalysisEnabled {
            scheduleAnalysis(for: story.objectID, input: .visual(url), context: context)
        }
    }

    /// Re-runs analysis for an existing story. Skips overwriting fields the user has
    /// edited manually. A PDF still in iCloud is downloaded first (see `UbiquitousFile`).
    static func reanalyze(
        story: CDStory,
        context: NSManagedObjectContext
    ) async {
        guard let url = await StoryFileStorage.storage.readyURL(
            bookmark: story.pdfFileBookmark,
            relativePath: story.pdfFileRelativePath
        ) else {
            story.analysisStatus = .failed
            story.analysisErrorMessage = "Couldn't find this story's PDF. Delete the story and add the PDF again."
            _ = context.safeSave()
            return
        }

        guard let extracted = StoryAnalyzer.extractText(from: url) else {
            story.analysisStatus = .failed
            story.analysisErrorMessage = "Couldn't open this PDF. Add the details yourself."
            _ = context.safeSave()
            return
        }

        story.extractedTextHash = extracted.hash

        if StoryAnalyzer.hasUsableText(extracted.text) {
            story.analysisStatus = .analyzing
            story.analysisErrorMessage = ""
            _ = context.safeSave()
            scheduleAnalysis(for: story.objectID, input: .text(extracted.text), context: context)
        } else if StoryAnalyzer.isVisualAnalysisEnabled {
            story.analysisStatus = .analyzing
            story.analysisErrorMessage = ""
            _ = context.safeSave()
            scheduleAnalysis(for: story.objectID, input: .visual(url), context: context)
        } else {
            story.analysisStatus = .manual
            story.analysisErrorMessage = "Couldn't read the words in this PDF. Add the details yourself."
            _ = context.safeSave()
        }
    }

    // MARK: - Background analysis

    /// What the analyzer should look at: extracted text, or rendered pages for
    /// PDFs with no readable text layer.
    private enum AnalysisInput: Sendable {
        case text(String)
        case visual(URL)
    }

    private static func scheduleAnalysis(
        for objectID: NSManagedObjectID,
        input: AnalysisInput,
        context: NSManagedObjectContext
    ) {
        StoryImportQueue.shared.submit {
            do {
                let result: StoryAnalysisResult
                switch input {
                case .text(let text):
                    result = try await StoryAnalyzer.analyze(text: text)
                case .visual(let url):
                    result = try await StoryAnalyzer.analyzeVisually(url: url)
                }
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
            guard let story = context.existing(CDStory.self, objectID) else { return }
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
        // Stored on the story (synced and backed up), so it's the plain sentence,
        // never the raw error; the raw one goes to the log.
        if !(error is StoryAnalyzerError) {
            logger.error("Story analysis failed: \(error.localizedDescription, privacy: .public)")
        }
        let otherFailureMessage = AppErrorMessages.aiMessage(for: error, fallback: StoryAnalyzerError.couldNotRead)
        await context.perform {
            guard let story = context.existing(CDStory.self, objectID) else { return }
            if let analyzerError = error as? StoryAnalyzerError {
                switch analyzerError {
                case .aiUnavailable:
                    story.analysisStatus = .manual
                case .insufficientText:
                    story.analysisStatus = .manual
                    story.analysisErrorMessage = "Couldn't read the words in this PDF. Add the details yourself."
                case .unreadablePDF:
                    story.analysisStatus = .manual
                    story.analysisErrorMessage = "Couldn't open this PDF's pages. Add the details yourself."
                case .timedOut:
                    story.analysisStatus = .failed
                    story.analysisErrorMessage = "This took too long. Try again."
                case .generationFailed(let message):
                    story.analysisStatus = .failed
                    story.analysisErrorMessage = message
                }
            } else {
                story.analysisStatus = .failed
                story.analysisErrorMessage = otherFailureMessage
            }
            story.modifiedAt = Date()
            _ = context.safeSave()
        }
    }
}
