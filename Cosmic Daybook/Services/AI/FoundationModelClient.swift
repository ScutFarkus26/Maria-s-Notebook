//
//  FoundationModelClient.swift
//  Cosmic Daybook
//
//  Shared MCPClientProtocol plumbing for the two FoundationModels-backed
//  clients: on-device (`LocalModelClient`) and Private Cloud Compute
//  (`PrivateCloudModelClient`). Each client supplies only what differs — its
//  availability check and how it configures a session and its generation
//  options. The availability guard, instruction assembly, response handling,
//  JSON validation and error mapping live here, once.
//

import Foundation
import Synchronization

/// A model's answer read as the JSON a caller asked for.
nonisolated enum ModelJSONText {
    /// The answer as JSON text the caller can parse, or nil when it holds none.
    ///
    /// The model is told to send bare JSON, but the on-device one often wraps
    /// it in a ```json fence or a sentence ("Here are the matches: …"), and
    /// Parsha suggestions, lesson planning, insights and story matching all
    /// failed as unreadable (bug hunt 2026-10-17 #15). A fence, and anything
    /// outside the outermost {…} or […], are dropped first.
    static func validated(_ answer: String) -> String? {
        let text = outermostJSON(in: withoutCodeFence(answer.trimmed()))
        guard (try? JSONSerialization.jsonObject(with: Data(text.utf8))) != nil else { return nil }
        return text
    }

    /// `text` without a Markdown code fence around it, language tag and all.
    private static func withoutCodeFence(_ text: String) -> String {
        guard text.hasPrefix("```") else { return text }
        var body = text.dropFirst(3)
        if let lineBreak = body.firstIndex(where: \.isNewline) {
            body = body[body.index(after: lineBreak)...]
        } else {
            body = body.drop(while: \.isLetter)
        }
        if body.hasSuffix("```") {
            body = body.dropLast(3)
        }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// From the first `{` or `[` to the last matching closer, or `text` as it
    /// is when it has no such span.
    private static func outermostJSON(in text: String) -> String {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }) else { return text }
        let closer: Character = text[start] == "{" ? "}" : "]"
        guard let end = text.lastIndex(of: closer), start < end else { return text }
        return String(text[start...end])
    }
}

/// Holds a model request to the caller's time limit. Foundation Models has no
/// timeout option (`GenerationOptions` has none), so the clients ignored the
/// limit their callers passed and a stuck request waited as long as the model
/// took (bug hunt 2026-10-17 #16). The request races a timer instead, and the
/// loser is cancelled.
nonisolated enum ModelRequestTimeout {
    /// `request`'s answer, or `LocalModelError.generationFailed` with
    /// Apple Intelligence's "took too long" sentence once `seconds` pass.
    /// Without a limit (nil, or not positive) the request just runs.
    ///
    /// The request and the timer are tasks of their own, and the first to
    /// finish answers; the other is cancelled, not waited for. A task group
    /// waits for every child, so a model that ignored cancellation held
    /// "took too long" until it stopped (review (b) 2026-10-17, #7).
    /// Cancelling the caller answers `CancellationError` at once, the same way.
    static func run<Answer: Sendable>(
        limit seconds: TimeInterval?,
        _ request: @escaping @Sendable () async throws -> Answer
    ) async throws -> Answer {
        guard let seconds, seconds > 0 else { return try await request() }
        try Task.checkCancellation()
        let race = FirstToFinish<Answer>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.wait(continuation)
                race.add(Task {
                    do {
                        race.finish(.success(try await request()))
                    } catch {
                        race.finish(.failure(error))
                    }
                })
                race.add(Task {
                    // Cancelled: the request answered first.
                    guard (try? await Task.sleep(for: .seconds(seconds))) != nil else { return }
                    race.finish(.failure(LocalModelError.generationFailed(AppleIntelligenceMessages.timedOut)))
                })
            }
        } onCancel: {
            race.finish(.failure(CancellationError()))
        }
    }
}

/// `ModelRequestTimeout`'s race: the first outcome goes to the waiting caller,
/// once, and every task still running is cancelled.
private nonisolated final class FirstToFinish<Answer: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Answer, any Error>?
        var outcome: Result<Answer, any Error>?
        var tasks: [Task<Void, Never>] = []
    }

    private let state = Mutex(State())

    /// The caller's wait; answered at once when an outcome came first.
    func wait(_ continuation: CheckedContinuation<Answer, any Error>) {
        let outcome = state.withLock { state -> Result<Answer, any Error>? in
            if state.outcome == nil { state.continuation = continuation }
            return state.outcome
        }
        if let outcome { continuation.resume(with: outcome) }
    }

    /// A task in the race; cancelled at once when the race is already over.
    func add(_ task: Task<Void, Never>) {
        let over = state.withLock { state -> Bool in
            if state.outcome == nil { state.tasks.append(task) }
            return state.outcome != nil
        }
        if over { task.cancel() }
    }

    /// The first call wins; later ones are ignored.
    func finish(_ outcome: Result<Answer, any Error>) {
        typealias Taken = (CheckedContinuation<Answer, any Error>?, [Task<Void, Never>])
        let (continuation, tasks) = state.withLock { state -> Taken in
            guard state.outcome == nil else { return (nil, []) }
            state.outcome = outcome
            defer {
                state.continuation = nil
                state.tasks = []
            }
            return (state.continuation, state.tasks)
        }
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: outcome)
    }
}

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

protocol FoundationModelClient: RoutableModelClient {
    /// A session configured for this client's model.
    func makeSession(instructions: String) -> LanguageModelSession

    /// The options this client sends with a single response request.
    func generationOptions(temperature: Double, maxTokens: Int?) -> GenerationOptions
}

// MARK: - Shared Request Handling

extension FoundationModelClient {

    /// Appended to instructions when the caller needs raw JSON back.
    static var jsonOnlyInstruction: String {
        "\n\nIMPORTANT: Return ONLY valid JSON. No markdown, no code blocks."
    }

    /// Throws `LocalModelError.unavailable` when the model cannot be reached.
    func requireAvailable() throws {
        guard isAvailable else {
            throw LocalModelError.unavailable(unavailabilityReason)
        }
    }

    /// Plain-text response for `instructions` + `prompt`, within `timeout`
    /// seconds when one is given.
    func respond(
        prompt: String,
        instructions: String,
        temperature: Double,
        maxTokens: Int?,
        timeout: TimeInterval?
    ) async throws -> String {
        try requireAvailable()

        let session = makeSession(instructions: instructions)
        let options = generationOptions(temperature: temperature, maxTokens: maxTokens)

        do {
            return try await ModelRequestTimeout.run(limit: timeout) {
                try await session.respond(to: prompt, options: options).content
            }
        } catch let error as LanguageModelError {
            throw LocalModelError.fromLanguageModel(error)
        }
    }

    /// JSON response for `instructions` + `prompt`, validated before
    /// returning, within `timeout` seconds when one is given. A request that
    /// was called off stays a cancellation rather than "unreadable".
    func respondJSON(
        prompt: String,
        instructions: String,
        temperature: Double,
        maxTokens: Int?,
        timeout: TimeInterval?
    ) async throws -> String {
        try requireAvailable()

        let session = makeSession(instructions: instructions + Self.jsonOnlyInstruction)
        let options = generationOptions(temperature: temperature, maxTokens: maxTokens)

        let content: String
        do {
            content = try await ModelRequestTimeout.run(limit: timeout) {
                try await session.respond(to: prompt, options: options).content
            }
        } catch let error as LanguageModelError {
            throw LocalModelError.fromLanguageModel(error)
        }
        guard let json = ModelJSONText.validated(content) else {
            throw LocalModelError.invalidJSON
        }
        return json
    }
}

// MARK: - MCPClientProtocol

extension FoundationModelClient {

    func generateText(prompt: String, temperature: Double) async throws -> String {
        try await respond(
            prompt: prompt, instructions: AIPrompts.generalAssistant,
            temperature: temperature, maxTokens: nil, timeout: nil
        )
    }

    func generateText(
        prompt: String,
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int?,
        timeout: TimeInterval?
    ) async throws -> String {
        try await respond(
            prompt: prompt, instructions: systemMessage ?? AIPrompts.generalAssistant,
            temperature: temperature, maxTokens: maxTokens, timeout: timeout
        )
    }

    func generateStructuredJSON(prompt: String, temperature: Double) async throws -> String {
        try await respondJSON(
            prompt: prompt, instructions: AIPrompts.generalAssistant,
            temperature: temperature, maxTokens: nil, timeout: nil
        )
    }

    func generateStructuredJSON(
        prompt: String,
        systemMessage: String?,
        temperature: Double,
        maxTokens: Int?,
        timeout: TimeInterval?
    ) async throws -> String {
        try await respondJSON(
            prompt: prompt, instructions: systemMessage ?? AIPrompts.generalAssistant,
            temperature: temperature, maxTokens: maxTokens, timeout: timeout
        )
    }
}

#endif
