//
//  TokenBudget.swift
//  Maria's Notebook
//
//  Token-based input budgeting for Apple's models. Replaces character-count
//  guessing with the framework's own tokenizer (tokenCount/contextSize, iOS 26.4+),
//  so "will this fit?" decisions match what the model actually sees.
//

import Foundation

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

/// Measures prompts against a model's real context window.
struct TokenBudget {
    let model: SystemLanguageModel

    init(model: SystemLanguageModel = .default) {
        self.model = model
    }

    /// Tokens to reserve for the model's reply.
    static let shortReply = 512
    static let draftReply = 1024

    /// Conservative fallback when the tokenizer is unavailable (~3 chars/token).
    private static let charsPerTokenFallback = 3

    var contextSize: Int { model.contextSize }

    /// True when `prompt` plus a reserved reply fits the model's context window.
    func fits(prompt: String, reserving replyTokens: Int = TokenBudget.shortReply) async -> Bool {
        let available = contextSize - replyTokens
        guard available > 0 else { return false }
        guard let tokens = try? await model.tokenCount(for: prompt) else {
            return prompt.count <= available * Self.charsPerTokenFallback
        }
        return tokens <= available
    }

    /// The largest prefix of `text` whose token count fits within `maxTokens`.
    /// Binary-searches on character count; the tokenizer runs on-device, so the
    /// handful of measurement rounds is cheap.
    func prefix(of text: String, fittingTokens maxTokens: Int) async -> String {
        guard maxTokens > 0 else { return "" }
        guard let total = try? await model.tokenCount(for: text) else {
            return String(text.prefix(maxTokens * Self.charsPerTokenFallback))
        }
        if total <= maxTokens { return text }

        var low = 0
        var high = text.count
        while low < high {
            let mid = (low + high + 1) / 2
            let candidate = String(text.prefix(mid))
            guard let tokens = try? await model.tokenCount(for: candidate) else {
                return String(text.prefix(maxTokens * Self.charsPerTokenFallback))
            }
            if tokens <= maxTokens {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return String(text.prefix(low))
    }
}

#endif
