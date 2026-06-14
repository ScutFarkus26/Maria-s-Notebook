//
//  AppleIntelligenceSheet+Generation.swift
//  Maria's Notebook
//
//  FoundationModels draft generation for AppleIntelligenceSheet. Split out of the
//  main view file so the view stays under SwiftLint's type/file length limits.
//

import SwiftUI

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

extension AppleIntelligenceSheet {
    @MainActor
    func generateWithFoundationModel(template: PromptTemplate, context: String) async {
        isGenerating = true
        generationError = nil

        let onDevice = LocalModelClient()
        let privateCloud = PrivateCloudModelClient()

        guard onDevice.isAvailable || privateCloud.isAvailable else {
            generationError = unavailabilityMessage()
            editorText = context
            isGenerating = false
            return
        }

        let prompt = """
        \(template.instruction)

        DATA:
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
        } catch let error as LocalModelError {
            let message = error.localizedDescription
            generationError = message
            editorText = context + "\n\n[Error: \(message)]"
        } catch let error as LanguageModelError {
            let message = userMessage(for: error)
            generationError = message
            editorText = context + "\n\n[Error: \(message)]"
        } catch {
            let message = AppErrorMessages.aiMessage(for: error)
            generationError = message
            editorText = context + "\n\n[Error: \(message)]"
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
                    temperature: 0.7, maxTokens: nil, model: nil, timeout: nil
                )
            }
        }

        do {
            return try await onDevice.generateText(
                prompt: prompt, systemMessage: AIPrompts.advancedAssistant,
                temperature: 0.7, maxTokens: nil, model: nil, timeout: nil
            )
        } catch LocalModelError.contextTooLarge where privateCloud.isAvailable {
            return try await privateCloud.generateDraft(
                prompt: prompt,
                instructions: AIPrompts.advancedAssistant,
                reasoning: .moderate
            )
        }
    }

    private func unavailabilityMessage() -> String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return ""
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Please enable Apple Intelligence in Settings to use this feature."
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is downloading. Please try again later."
        case .unavailable:
            return "Apple Intelligence is not available."
        }
    }

    private func userMessage(for error: LanguageModelError) -> String {
        switch error {
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .contextSizeExceeded:
            return "The data is too large for on-device processing. Try selecting fewer notes."
        case .unsupportedLanguageOrLocale:
            return "This language is not supported by Apple Intelligence."
        case .refusal:
            return "The request could not be processed due to content restrictions."
        case .timeout:
            return "The request timed out. Please try again."
        default:
            return "Apple Intelligence encountered an unexpected issue. Try again."
        }
    }
}

#endif
