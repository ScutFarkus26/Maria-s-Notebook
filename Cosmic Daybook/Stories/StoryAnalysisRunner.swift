import Foundation
import CoreData
import OSLog

/// Runs a story's analysis in the background (`StoryImportQueue`) and writes
/// the result onto the story: after an import (`LibraryImportService`) and
/// when the guide asks again from the story's detail.
enum StoryAnalysisRunner {
    private static let logger = Logger.stories

    /// Kicks off async analysis after import when AI is on: text analysis when the
    /// PDF has readable text, visual page analysis otherwise (scanned/picture books).
    static func scheduleInitialAnalysis(
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
        guard let url = await LibraryFileStorage.stories.readyURL(
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
