import Foundation
@preconcurrency import PDFKit
import CryptoKit
import OSLog

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

/// Result of analyzing a story PDF.
struct StoryAnalysisResult: Sendable {
    var title: String
    var summary: String
    var themes: [String]
    var gradeMin: StoryGrade
    var gradeMax: StoryGrade
    var modelVersion: String
}

enum StoryAnalyzerError: LocalizedError {
    case aiUnavailable
    case insufficientText
    case generationFailed(message: String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .aiUnavailable:
            return "Apple Intelligence is unavailable on this device."
        case .insufficientText:
            return "Couldn't read enough text from the PDF to analyze."
        case .generationFailed(let message):
            return message
        case .timedOut:
            return "The analysis took too long and was cancelled."
        }
    }
}

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
@available(macOS 26.0, iOS 26.0, *)
@Generable(description: "Extracted metadata for a children's or educational story")
struct StoryAnalysisAI {
    @Guide(description: "The story's title as it appears on the cover or first page; concise, no quotes")
    let title: String

    @Guide(description: "A 1-2 sentence plot summary suitable for a teacher's reference")
    let summary: String

    @Guide(
        description: "3-7 short thematic tags describing the story's main themes "
            + "(e.g. friendship, courage, nature, family). Each tag is one or two words, lowercase.",
        .count(3...7)
    )
    let themes: [String]

    @Guide(description: "Lowest grade level for which this story is appropriate")
    let gradeMin: StoryGradeAI

    @Guide(description: "Highest grade level for which this story is appropriate")
    let gradeMax: StoryGradeAI
}
#endif

/// Performs PDF text extraction and (when Apple Intelligence is available) generates
/// title/themes/grade-level metadata for a story.
enum StoryAnalyzer {
    private static let logger = Logger.stories
    private static let maxPagesToRead = 10
    private static let maxCharacters = 12_000
    private static let analysisTimeout: Duration = .seconds(30)

    /// True if on-device AI analysis is available right now.
    static var isAIEnabled: Bool {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) {
            return SystemLanguageModel.default.isAvailable
        }
        #endif
        return false
    }

    /// Extracts up to the first 10 pages of text from a PDF.
    /// Returns the trimmed text and a hash for staleness detection.
    static func extractText(from url: URL) -> (text: String, hash: String, pageCount: Int)? {
        guard let document = PDFDocument(url: url) else { return nil }
        let totalPages = document.pageCount
        let pagesToRead = Swift.min(totalPages, maxPagesToRead)

        var pieces: [String] = []
        for index in 0..<pagesToRead {
            if let page = document.page(at: index), let text = page.string {
                pieces.append(text)
            }
        }

        let combined = pieces.joined(separator: "\n\n")
        let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
        let hash = sha256(trimmed)
        return (trimmed, hash, totalPages)
    }

    private static func sha256(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Truncates extracted text to a model-friendly size.
    static func truncate(_ text: String) -> String {
        guard text.count > maxCharacters else { return text }
        return String(text.prefix(maxCharacters))
    }

    /// True if a hunk of extracted text has enough content for the LLM to reason about.
    static func hasUsableText(_ text: String) -> Bool {
        text.count >= 200
    }

    /// Runs AI analysis on the supplied text. Throws a typed error on failure.
    static func analyze(text: String) async throws -> StoryAnalysisResult {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        guard #available(macOS 26.0, iOS 26.0, *) else {
            throw StoryAnalyzerError.aiUnavailable
        }
        guard SystemLanguageModel.default.isAvailable else {
            throw StoryAnalyzerError.aiUnavailable
        }
        guard hasUsableText(text) else {
            throw StoryAnalyzerError.insufficientText
        }

        let prompt = truncate(text)
        let instructions = "You are a children's-literature librarian. "
            + "Read the supplied story excerpt and extract structured metadata. "
            + "Choose grade levels conservatively. "
            + "Themes should be lowercase single words or two-word phrases."
        let session = LanguageModelSession(instructions: instructions)

        do {
            let result: StoryAnalysisResult = try await withTimeout(analysisTimeout) {
                let response = try await session.respond(
                    to: "Analyze this story excerpt:\n\n\(prompt)",
                    generating: StoryAnalysisAI.self
                )
                let content = response.content
                return StoryAnalysisResult(
                    title: cleanTitle(content.title),
                    summary: content.summary.trimmingCharacters(in: .whitespacesAndNewlines),
                    themes: cleanThemes(content.themes),
                    gradeMin: content.gradeMin.asStoryGrade,
                    gradeMax: content.gradeMax.asStoryGrade,
                    modelVersion: "FoundationModels.system"
                )
            }
            return result
        } catch is TimeoutError {
            throw StoryAnalyzerError.timedOut
        } catch let error as LanguageModelSession.GenerationError {
            logger.warning("Story analysis generation error: \(String(describing: error), privacy: .public)")
            throw StoryAnalyzerError.generationFailed(message: userMessage(for: error))
        } catch {
            logger.warning("Story analysis failed: \(error.localizedDescription, privacy: .public)")
            throw StoryAnalyzerError.generationFailed(message: error.localizedDescription)
        }
        #else
        throw StoryAnalyzerError.aiUnavailable
        #endif
    }

    // MARK: - Cleaning

    private static func cleanTitle(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        if trimmed.count > 120 {
            trimmed = String(trimmed.prefix(120))
        }
        return trimmed
    }

    /// Caps to 7 themes, dedupes case-insensitively, trims, and rejects very long entries.
    static func cleanThemes(_ raw: [String]) -> [String] {
        var seen: Set<String> = []
        var output: [String] = []
        for entry in raw {
            let trimmed = entry.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "_", with: " ")
                .lowercased()
            guard !trimmed.isEmpty, trimmed.count <= 30 else { continue }
            if seen.insert(trimmed).inserted {
                output.append(trimmed)
            }
            if output.count >= 7 { break }
        }
        return output
    }

    // MARK: - Timeout helper

    private struct TimeoutError: Error {}

    private static func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TimeoutError()
            }
            guard let first = try await group.next() else {
                throw TimeoutError()
            }
            group.cancelAll()
            return first
        }
    }

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private static func userMessage(for error: LanguageModelSession.GenerationError) -> String {
        switch error {
        case .assetsUnavailable:
            return "Apple Intelligence assets are not available right now."
        case .exceededContextWindowSize:
            return "The story is too long for the on-device model."
        case .rateLimited:
            return "Apple Intelligence is busy. Try again in a moment."
        case .unsupportedLanguageOrLocale:
            return "This language is not supported by Apple Intelligence."
        case .refusal:
            return "Apple Intelligence declined to analyze this story."
        default:
            return "Apple Intelligence encountered an unexpected error."
        }
    }
    #endif
}
