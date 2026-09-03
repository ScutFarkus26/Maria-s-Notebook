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
    case unreadablePDF
    case generationFailed(message: String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .aiUnavailable:
            return "Apple Intelligence is unavailable on this device."
        case .insufficientText:
            return "Couldn't read enough text from the PDF to analyze."
        case .unreadablePDF:
            return "Couldn't read this PDF's pages."
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
nonisolated enum StoryAnalyzer {
    private static let logger = Logger.stories
    private static let maxPagesToRead = 10
    private static let analysisTimeout: Duration = .seconds(30)
    // Image understanding is slower than text: a few rendered pages cost far
    // more tokens than a text excerpt, so give the visual path extra headroom.
    private static let visualAnalysisTimeout: Duration = .seconds(90)
    private static let maxPagesToRender = 3
    private static let renderedPageMaxDimension: CGFloat = 1_024
    // Headroom for instructions, the generation schema, and the response.
    private static let promptTokenReserve = 1_500

    /// True if on-device AI analysis is available right now.
    static var isAIEnabled: Bool {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        return SystemLanguageModel.default.isAvailable
        #else
        return false
        #endif
    }

    /// True if the on-device model can analyze page images (scanned/picture books).
    static var isVisualAnalysisEnabled: Bool {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        let model = SystemLanguageModel.default
        return model.isAvailable && model.capabilities.contains(.vision)
        #else
        return false
        #endif
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

    /// True if a hunk of extracted text has enough content for the LLM to reason about.
    static func hasUsableText(_ text: String) -> Bool {
        text.count >= 200
    }

    private static let textInstructions = "You are a children's-literature librarian. "
        + "Read the supplied story excerpt and extract structured metadata. "
        + "Choose grade levels conservatively. "
        + "Themes should be lowercase single words or two-word phrases."

    /// Runs AI analysis on the supplied text. Throws a typed error on failure.
    static func analyze(text: String) async throws -> StoryAnalysisResult {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        guard SystemLanguageModel.default.isAvailable else {
            throw StoryAnalyzerError.aiUnavailable
        }
        guard hasUsableText(text) else {
            throw StoryAnalyzerError.insufficientText
        }

        // Clamp the excerpt to what actually fits the model's context window,
        // measured in real tokens rather than guessed from character counts.
        let budget = TokenBudget()
        let maxInputTokens = max(1_000, budget.contextSize - promptTokenReserve)
        let prompt = await budget.prefix(of: text, fittingTokens: maxInputTokens)
        let session = LanguageModelSession(instructions: textInstructions)

        do {
            let result: StoryAnalysisResult = try await withTimeout(analysisTimeout) {
                let response = try await session.respond(
                    to: "Analyze this story excerpt:\n\n\(prompt)",
                    generating: StoryAnalysisAI.self
                )
                return makeResult(from: response.content, modelVersion: "FoundationModels.system")
            }
            return result
        } catch is TimeoutError {
            throw StoryAnalyzerError.timedOut
        } catch let error as LanguageModelError {
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

    /// Analyzes a story from rendered page images — for scanned PDFs and picture
    /// books where text extraction comes up empty. Renders the first pages and
    /// asks the vision-capable on-device model to read them directly.
    static func analyzeVisually(url: URL) async throws -> StoryAnalysisResult {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        guard isVisualAnalysisEnabled else {
            throw StoryAnalyzerError.aiUnavailable
        }

        let instructions = "You are a children's-literature librarian. "
            + "You are shown the first pages of a story (cover first). "
            + "Read any visible text and use the illustrations to extract structured metadata. "
            + "Choose grade levels conservatively. "
            + "Themes should be lowercase single words or two-word phrases."

        do {
            // Page images and attachments aren't Sendable, so everything from
            // rendering to the request is built inside the timeout task; only
            // the (Sendable) file URL is captured.
            let result: StoryAnalysisResult = try await withTimeout(visualAnalysisTimeout) {
                let images = renderPageImages(from: url)
                guard !images.isEmpty else {
                    throw StoryAnalyzerError.unreadablePDF
                }
                let session = LanguageModelSession(instructions: instructions)
                let attachments = images.map { Attachment($0) }
                let response = try await session.respond(generating: StoryAnalysisAI.self) {
                    "Analyze the story shown on these pages:"
                    attachments
                }
                return makeResult(from: response.content, modelVersion: "FoundationModels.system+vision")
            }
            return result
        } catch is TimeoutError {
            throw StoryAnalyzerError.timedOut
        } catch let error as StoryAnalyzerError {
            throw error
        } catch let error as LanguageModelError {
            logger.warning("Visual story analysis generation error: \(String(describing: error), privacy: .public)")
            throw StoryAnalyzerError.generationFailed(message: userMessage(for: error))
        } catch {
            logger.warning("Visual story analysis failed: \(error.localizedDescription, privacy: .public)")
            throw StoryAnalyzerError.generationFailed(message: error.localizedDescription)
        }
        #else
        throw StoryAnalyzerError.aiUnavailable
        #endif
    }

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    private static func makeResult(
        from content: StoryAnalysisAI,
        modelVersion: String
    ) -> StoryAnalysisResult {
        StoryAnalysisResult(
            title: cleanTitle(content.title),
            summary: content.summary.trimmingCharacters(in: .whitespacesAndNewlines),
            themes: cleanThemes(content.themes),
            gradeMin: content.gradeMin.asStoryGrade,
            gradeMax: content.gradeMax.asStoryGrade,
            modelVersion: modelVersion
        )
    }
    #endif

    /// Renders the first pages of a PDF to bitmaps sized for the model.
    private static func renderPageImages(from url: URL) -> [CGImage] {
        guard let document = PDFDocument(url: url) else { return [] }
        let count = Swift.min(document.pageCount, maxPagesToRender)
        var images: [CGImage] = []
        for index in 0..<count {
            guard let page = document.page(at: index) else { continue }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { continue }
            let scale = renderedPageMaxDimension / Swift.max(bounds.width, bounds.height)
            let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
            let thumbnail = page.thumbnail(of: size, for: .mediaBox)
            #if os(macOS)
            var rect = CGRect(origin: .zero, size: thumbnail.size)
            if let cgImage = thumbnail.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                images.append(cgImage)
            }
            #else
            if let cgImage = thumbnail.cgImage {
                images.append(cgImage)
            }
            #endif
        }
        return images
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
        try await withThrowingTaskGroup(of: T.self) { sequence in
            sequence.addTask {
                try await operation()
            }
            sequence.addTask {
                try await Task.sleep(for: duration)
                throw TimeoutError()
            }
            guard let first = try await sequence.next() else {
                throw TimeoutError()
            }
            sequence.cancelAll()
            return first
        }
    }

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    @available(macOS 26.0, iOS 26.0, *)
    private static func userMessage(for error: LanguageModelError) -> String {
        switch error {
        case .contextSizeExceeded:
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
