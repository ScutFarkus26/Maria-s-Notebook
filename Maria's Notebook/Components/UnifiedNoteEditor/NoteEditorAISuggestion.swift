// NoteEditorAISuggestion.swift
// AI suggestion functionality for UnifiedNoteEditor - extracted for maintainability

import SwiftUI
import CoreData

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

// MARK: - AI Suggestion Extension

extension UnifiedNoteEditor {

    /// The note's photo, downsampled for AI input — only when the on-device
    /// model can actually look at it.
    @MainActor
    var noteImageForAI: CGImage? {
        guard SystemLanguageModel.default.capabilities.contains(.vision),
              let path = imagePath else { return nil }
        return PhotoStorageService.loadCGImageForAI(filename: path)
    }

    /// Drafts an on-device AI description of the attached photo into the note body.
    /// Referenced from `photoPickerSection` in NoteEditorSections.swift.
    @ViewBuilder
    var describePhotoButton: some View {
        if imagePath != nil, SystemLanguageModel.default.capabilities.contains(.vision) {
            Button {
                Task { await describePhotoIntoNote() }
            } label: {
                Label(
                    isDescribingPhoto ? "Describing…" : "Describe Photo",
                    systemImage: "text.below.photo"
                )
                .font(AppTheme.ScaledFont.body)
            }
            .disabled(isDescribingPhoto)
            .help("Draft a description of the photo into the note")
        }
    }

    @MainActor
    // swiftlint:disable:next function_body_length
    func suggestTagsAndScope() async {
        let noteImage = noteImageForAI
        guard !bodyText.trimmed().isEmpty || noteImage != nil else { return }

        guard SystemLanguageModel.default.isAvailable else {
            self.suggestionError = appleIntelligenceUnavailableMessage()
            return
        }

        isSuggesting = true
        defer { isSuggesting = false }

        let session = LanguageModelSession(
            instructions: AIPrompts.noteClassification
        )
        do {
            let noteText = bodyText.trimmed().isEmpty
                ? "(no text yet — classify from the attached photo)"
                : bodyText
            let response: LanguageModelSession.Response<NoteTagSuggestion>
            if let noteImage {
                response = try await session.respond(
                    generating: NoteTagSuggestion.self,
                    options: .init(temperature: 0.2)
                ) {
                    AIPrompts.classifyNote(noteText)
                    "A photo attached to the note is included; use it as additional context."
                    Attachment(noteImage)
                }
            } else {
                response = try await session.respond(
                    to: AIPrompts.classifyNote(noteText),
                    generating: NoteTagSuggestion.self,
                    options: .init(temperature: 0.2)
                )
            }
            let content = response.content

            // Convert suggested tag names to tag strings with appropriate colors
            let suggestedTags: [String] = content.suggestedTags.map { tagName in
                let normalized = tagName.trimmed().lowercased()
                // Check if it maps to a known category color
                let color = TagHelper.colorForNoteCategory(normalized)
                let displayName = tagName.trimmed().prefix(1).uppercased() + tagName.trimmed().dropFirst()
                return TagHelper.createTag(name: displayName, color: color)
            }

            let ids: [UUID] = content.studentIdentifiers.compactMap { ident in
                let token = ident.folding(options: .diacriticInsensitive, locale: .current).trimmed().lowercased()
                return students.first(where: { s in
                    let first = s.firstName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    let last = s.lastName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    let nick = (s.nickname ?? "").folding(options: .diacriticInsensitive, locale: .current).lowercased()
                    let full = (first + " " + last)
                    return token == full || token == first || (!nick.isEmpty && token == nick)
                })?.id
            }

            self.proposedTags = suggestedTags
            self.proposedStudentIDs = Array(Set(ids))
            self.showingSuggestionSheet = true
        } catch let error as LanguageModelError {
            self.suggestionError = suggestionMessage(for: error)
        } catch {
            self.suggestionError = AppErrorMessages.aiMessage(for: error)
        }
    }

    /// Drafts a 1-2 sentence factual description of the attached photo and
    /// appends it to the note body. Runs fully on-device.
    @MainActor
    func describePhotoIntoNote() async {
        guard SystemLanguageModel.default.isAvailable else {
            self.suggestionError = appleIntelligenceUnavailableMessage()
            return
        }
        guard let noteImage = noteImageForAI else {
            self.suggestionError = "Photo description needs a model with image understanding."
            return
        }

        isDescribingPhoto = true
        defer { isDescribingPhoto = false }

        let session = LanguageModelSession(instructions: AIPrompts.generalAssistant)
        do {
            let response = try await session.respond(options: .init(temperature: 0.3)) {
                "Describe this photo of classroom work for a Montessori observation note. "
                    + "Write one or two factual sentences about the work shown "
                    + "(materials, subject area, stage of completion). "
                    + "Do not guess student names or invent details you can't see."
                Attachment(noteImage)
            }
            let description = response.content.trimmed()
            guard !description.isEmpty else { return }
            adaptiveWithAnimation {
                bodyText = bodyText.trimmed().isEmpty
                    ? description
                    : bodyText.trimmed() + "\n\n" + description
            }
        } catch let error as LanguageModelError {
            self.suggestionError = suggestionMessage(for: error)
        } catch {
            self.suggestionError = AppErrorMessages.aiMessage(for: error)
        }
    }

    // MARK: - Shared error text

    private func appleIntelligenceUnavailableMessage() -> String {
        switch SystemLanguageModel.default.availability {
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Please enable Apple Intelligence in Settings to use this feature."
        case .unavailable(.deviceNotEligible):
            return "This device does not support Apple Intelligence."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is downloading. Please try again later."
        default:
            return "Apple Intelligence is not available."
        }
    }

    private func suggestionMessage(for error: LanguageModelError) -> String {
        switch error {
        case .rateLimited:
            return "Too many requests. Please wait a moment and try again."
        case .contextSizeExceeded:
            return "The note is too long for on-device processing. Try with a shorter note."
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

// MARK: - Suggestion Preview Sheet

struct SuggestionPreviewSheet: View {
    let proposedTags: [String]
    let proposedStudentIDs: [UUID]
    let allStudents: [CDStudent]
    let onApply: ([String]) -> Void
    let onCancel: () -> Void

    @State private var selectedTags: Set<String> = []

    private func name(for id: UUID) -> String {
        if let s = allStudents.first(where: { $0.id == id }) {
            let first = s.firstName.trimmed()
            let lastI = s.lastName.first.map { String($0).uppercased() } ?? ""
            return lastI.isEmpty ? first : "\(first) \(lastI)."
        }
        return "Unknown"
    }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text("Suggested Tags")
                .font(AppTheme.ScaledFont.titleMedium)
            if !proposedTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tags:").bold()
                    FlowLayout(spacing: 8) {
                        ForEach(proposedTags, id: \.self) { tag in
                            Button {
                                if selectedTags.contains(tag) {
                                    selectedTags.remove(tag)
                                } else {
                                    selectedTags.insert(tag)
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    TagBadge(tag: tag)
                                    if selectedTags.contains(tag) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 12))
                                            .foregroundStyle(AppColors.success)
                                    }
                                }
                                .opacity(selectedTags.contains(tag) ? 1.0 : 0.5)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if !proposedStudentIDs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Scope:").bold()
                    ForEach(proposedStudentIDs, id: \.self) { id in
                        Text(name(for: id))
                    }
                }
            } else {
                HStack { Text("Scope:").bold(); Text("All Students") }
            }
            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                Button("Apply") { onApply(Array(selectedTags)) }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .presentationSizingFitted()
        .onAppear { selectedTags = Set(proposedTags) }
        #else
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if !proposedTags.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Tags:").bold()
                        FlowLayout(spacing: 8) {
                            ForEach(proposedTags, id: \.self) { tag in
                                Button {
                                    if selectedTags.contains(tag) {
                                        selectedTags.remove(tag)
                                    } else {
                                        selectedTags.insert(tag)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        TagBadge(tag: tag)
                                        if selectedTags.contains(tag) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(AppColors.success)
                                        }
                                    }
                                    .opacity(selectedTags.contains(tag) ? 1.0 : 0.5)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if !proposedStudentIDs.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Scope:").bold()
                        ForEach(proposedStudentIDs, id: \.self) { id in
                            Text(name(for: id))
                        }
                    }
                } else {
                    HStack { Text("Scope:").bold(); Text("All Students") }
                }
                Spacer()
            }
            .padding(20)
            .navigationTitle("Suggested Tags")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { onApply(Array(selectedTags)) } }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .onAppear { selectedTags = Set(proposedTags) }
        #endif
    }
}
#endif
