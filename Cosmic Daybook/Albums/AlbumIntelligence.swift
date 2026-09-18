// Apple Intelligence over the teaching albums, via the FoundationModels
// framework: availability gating (with user-facing explanations), the
// conversational Ask pipeline (retrieve excerpts → prompt the on-device model
// → answer with citations), and one-shot lesson summaries.

import Foundation

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels
#endif

/// On-device Apple Intelligence features for the album library.
/// Everything runs locally — album content never leaves the device.
@Observable
final class AlbumIntelligence {

    enum AlbumIntelligenceError: LocalizedError {
        case unavailable

        var errorDescription: String? {
            "Apple Intelligence isn't available in this build."
        }
    }

    /// Whether the on-device model can take requests right now.
    ///
    /// Stored, not computed: `SystemLanguageModel.default.availability` is a
    /// synchronous call into the model service, and the album toolbar's
    /// Summarize item reads this in `.disabled` and `.help` — i.e. inside
    /// AppKit's toolbar layout pass. Probing the framework from there is what
    /// tripped "NSToolbarItemViewer's min/max size is nan" on 2026-09-10
    /// (four `ModelBundle: Creating` log lines, then the assertion). The probe
    /// now runs off the main thread and only its result is observed.
    private(set) var isAvailable = false

    /// Why the model is unavailable, in words the guide can act on; `nil`
    /// when it is available. Same probe as `isAvailable`.
    private(set) var unavailableExplanation: String? = AlbumIntelligence.notProbedExplanation

    private static let notProbedExplanation = "Checking whether Apple Intelligence is available…"

    init() {
        refreshAvailability()
    }

    /// Re-probes availability off the main thread and publishes the result.
    /// Call it when a view that gates on availability appears, so a model that
    /// finished downloading since launch is picked up.
    func refreshAvailability() {
        Task { [weak self] in
            let probe = await Task.detached(priority: .utility) { Self.probeAvailability() }.value
            guard let self else { return }
            if isAvailable != probe.available { isAvailable = probe.available }
            if unavailableExplanation != probe.explanation { unavailableExplanation = probe.explanation }
        }
    }

    nonisolated private static func probeAvailability() -> (available: Bool, explanation: String?) {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available:
            return (true, nil)
        case .unavailable(.deviceNotEligible):
            return (false, "This device doesn't support Apple Intelligence, so Ask and Summarize aren't "
                + "available. Search, bookmarks, and notes all still work.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return (false, "Turn on Apple Intelligence in System Settings to use Ask and Summarize.")
        case .unavailable(.modelNotReady):
            return (false, "The on-device model is still getting ready (it may be downloading). "
                + "Try again in a little while.")
        case .unavailable:
            return (false, "Apple Intelligence isn't available right now.")
        }
        #else
        return (false, "Ask and Summarize need an Apple Intelligence build of the app. "
            + "Search, bookmarks, and notes all still work.")
        #endif
    }

    // MARK: Ask the albums

    struct Answer: Sendable {
        var text: String
        var sources: [AlbumAskSource]
    }

    private static let noMatchAnswer =
        "I couldn't find anything in the albums related to that. Try different words — "
        + "for example the name of a material or a topic like \"fraction insets\" or "
        + "\"parts of the flower\"."

    #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
    /// The running conversation. Kept across questions so follow-ups
    /// ("what materials does that need?") have context; reset explicitly
    /// or transparently when the on-device context window fills up.
    private var askSession: LanguageModelSession?
    #endif

    func resetConversation() {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        askSession = nil
        #endif
    }

    private static let askInstructions = """
        You are the assistant inside a Montessori elementary guide's personal teaching-albums app. \
        The user is the guide. Answer their questions using ONLY the numbered album excerpts provided \
        with each question. Later questions may refer back to earlier answers in this conversation. \
        Cite the excerpts you draw on with bracketed numbers like [1]. \
        Be concise (under 200 words), warm, and practical. \
        If the excerpts don't fully answer the question, say so and name the album or lesson \
        that looks most promising.
        """

    /// Retrieves the most relevant album pages, then asks the on-device model.
    /// `semanticBoost` carries per-lesson similarity from the semantic index so
    /// meaning-based matches surface even without keyword overlap.
    func answer(question: String, corpus: AlbumSearchCorpus,
                semanticBoost: [String: [Float]]? = nil) async throws -> Answer {
        let picks = await Task.detached(priority: .userInitiated) {
            AlbumSearchEngine.retrieve(question: question, corpus: corpus, limit: 5,
                                       boost: semanticBoost)
        }.value

        guard !picks.isEmpty else {
            return Answer(text: Self.noMatchAnswer, sources: [])
        }

        var sources: [AlbumAskSource] = []
        var excerpts = ""
        for (i, pick) in picks.enumerated() {
            let lesson = pick.album.lessons.last { $0.pageIndex <= pick.pageIndex }
            let lessonTitle = lesson?.title ?? pick.album.title
            sources.append(AlbumAskSource(id: i + 1, albumID: pick.album.id,
                                          albumTitle: pick.album.title,
                                          lessonTitle: lessonTitle, pageIndex: pick.pageIndex))
            let text = String(pick.album.texts[pick.pageIndex].prefix(1200))
            excerpts += "[\(i + 1)] From the \(pick.album.title) album, lesson “\(lessonTitle)”, "
                + "page \(pick.pageIndex + 1):\n\(text)\n\n"
        }

        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        let prompt = "Question: \(question)\n\nAlbum excerpts:\n\n\(excerpts)"
        let session = askSession ?? LanguageModelSession(instructions: Self.askInstructions)
        askSession = session
        do {
            let response = try await session.respond(to: prompt)
            return Answer(text: response.content, sources: sources)
        } catch {
            // Most likely the conversation outgrew the on-device context
            // window — start fresh and retry this question once.
            let fresh = LanguageModelSession(instructions: Self.askInstructions)
            askSession = fresh
            let response = try await fresh.respond(to: prompt)
            return Answer(text: response.content, sources: sources)
        }
        #else
        throw AlbumIntelligenceError.unavailable
        #endif
    }

    // MARK: Lesson summaries

    func summarize(lessonTitle: String, albumTitle: String, text: String) async throws -> String {
        #if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
        let session = LanguageModelSession(instructions: """
            You summarize Montessori album lessons so a guide can refresh quickly before presenting. \
            From the lesson text, give: the aim, the materials (if listed), and the key presentation \
            steps as a short numbered list. Under 180 words. Do not invent details that aren't in \
            the text.
            """)
        let prompt = "Lesson “\(lessonTitle)” from the \(albumTitle) album:\n\n"
            + String(text.prefix(6000))
        let response = try await session.respond(to: prompt)
        return response.content
        #else
        throw AlbumIntelligenceError.unavailable
        #endif
    }
}
