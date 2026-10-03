//
//  AppleIntelligenceSheet+Generation.swift
//  Cosmic Daybook
//
//  FoundationModels draft generation for AppleIntelligenceSheet. Split out of the
//  main view file so the view stays under SwiftLint's type/file length limits.
//

import OSLog
import SwiftUI

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

extension AppleIntelligenceSheet {
    func generateWithFoundationModel(template: PromptTemplate, context: String) async {
        isGenerating = true
        generationError = nil

        let onDevice = LocalModelClient()
        let privateCloud = PrivateCloudModelClient()

        guard onDevice.isAvailable || privateCloud.isAvailable else {
            generationError = unavailabilityMessage()
            isGenerating = false
            return
        }

        let prompt = """
        \(template.instruction)

        Notes:
        \(context)
        """

        do {
            let text = try await generateDraft(
                prompt: prompt, onDevice: onDevice, privateCloud: privateCloud
            )
            // Animate the text in (simple replacement for now)
            adaptiveWithAnimation {
                editorText = text
            }
        } catch let error as LanguageModelError {
            // The note text stays as it was; the banner says what went wrong.
            Self.logger.error("Writing help draft failed: \(error, privacy: .public)")
            generationError = userMessage(for: error)
        } catch LocalModelError.contextTooLarge {
            generationError = Self.tooManyNotes
        } catch {
            Self.logger.error("Writing help draft failed: \(error, privacy: .public)")
            generationError = AppErrorMessages.aiMessage(
                for: error,
                fallback: "Couldn't write the draft. Try again in a moment."
            )
        }

        isGenerating = false
    }

    /// Long-form drafts (report cards, weekly summaries) go to Private Cloud Compute
    /// when the input won't fit a quality on-device draft or on-device is unavailable.
    /// Small jobs stay on-device — faster and quota-free. Each path falls back to the
    /// other on failure (e.g. PCC daily quota reached, on-device context overflow).
    private func generateDraft(
        prompt: String,
        onDevice: LocalModelClient,
        privateCloud: PrivateCloudModelClient
    ) async throws -> String {
        var preferPrivateCloud = false
        if privateCloud.isAvailable {
            if onDevice.isAvailable {
                let budget = TokenBudget()
                preferPrivateCloud = await !budget.fits(
                    prompt: prompt, reserving: TokenBudget.draftReply
                )
            } else {
                preferPrivateCloud = true
            }
        }

        if preferPrivateCloud {
            do {
                return try await privateCloud.generateDraft(
                    prompt: prompt,
                    instructions: AIPrompts.advancedAssistant,
                    reasoning: .moderate
                )
            } catch let error as LocalModelError {
                guard onDevice.isAvailable else { throw error }
                return try await onDevice.generateText(
                    prompt: prompt, systemMessage: AIPrompts.advancedAssistant,
                    temperature: 0.7, maxTokens: nil, timeout: nil
                )
            }
        }

        do {
            return try await onDevice.generateText(
                prompt: prompt, systemMessage: AIPrompts.advancedAssistant,
                temperature: 0.7, maxTokens: nil, timeout: nil
            )
        } catch LocalModelError.contextTooLarge where privateCloud.isAvailable {
            return try await privateCloud.generateDraft(
                prompt: prompt,
                instructions: AIPrompts.advancedAssistant,
                reasoning: .moderate
            )
        }
    }

    private static let logger = Logger.ai
    private static let tooManyNotes =
        "That's too many notes to work with at once. Choose fewer notes and try again."

    private func unavailabilityMessage() -> String {
        AppleIntelligenceMessages.unavailableMessage(for: SystemLanguageModel.default.availability)
            ?? AppleIntelligenceMessages.notAvailable
    }

    private func userMessage(for error: LanguageModelError) -> String {
        AppleIntelligenceMessages.message(
            for: error,
            tooLong: Self.tooManyNotes,
            fallback: "Couldn't write the draft. Try again in a moment."
        )
    }
}

#endif
