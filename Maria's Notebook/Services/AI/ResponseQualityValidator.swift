//
//  ResponseQualityValidator.swift
//  Maria's Notebook
//
//  Validates local model responses to determine if cloud escalation should be offered.
//

import Foundation

/// Validates AI responses from local models to detect inadequate answers.
/// Used by the smart routing system to decide when to offer cloud escalation.
enum ResponseQualityValidator {

    struct ValidationResult {
        let isAdequate: Bool
        let reason: String?
    }

    /// Minimum response length (characters) for a non-trivial question.
    private static let minResponseLength = 20

    /// Question length threshold — questions shorter than this are considered "simple"
    /// and won't trigger length-based inadequacy checks.
    private static let simpleQuestionThreshold = 30

    /// Phrases that indicate the model couldn't answer properly.
    private static let failurePhrases: [String] = [
        "i don't have enough information",
        "i cannot",
        "i'm unable to",
        "i am unable to",
        "as an ai",
        "as a language model",
        "i don't have access",
        "i do not have access",
        "i'm not able to",
        "i am not able to",
        "sorry, i can't",
        "sorry, i cannot",
    ]

    /// Validates a response against quality heuristics.
    /// - Parameters:
    ///   - response: The AI-generated response text.
    ///   - request: The original user question/prompt.
    /// - Returns: A validation result indicating adequacy.
    static func validate(_ response: String, forRequest request: String) -> ValidationResult {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty response
        if trimmed.isEmpty {
            return ValidationResult(isAdequate: false, reason: "Empty response")
        }

        // Very short response for a non-trivial question
        let isSimpleQuestion = request.count < simpleQuestionThreshold
        if !isSimpleQuestion && trimmed.count < minResponseLength {
            return ValidationResult(isAdequate: false, reason: "Response too short for the question")
        }

        // Check for failure phrases
        let lowered = trimmed.lowercased()
        for phrase in failurePhrases {
            if lowered.contains(phrase) {
                return ValidationResult(isAdequate: false, reason: "Response indicates inability to answer")
            }
        }

        // Disproportionately short: question > 50 chars but answer < 30 chars
        if request.count > 50 && trimmed.count < 30 {
            return ValidationResult(isAdequate: false, reason: "Response disproportionately short")
        }

        return ValidationResult(isAdequate: true, reason: nil)
    }
}
