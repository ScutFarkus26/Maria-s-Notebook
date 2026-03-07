// NoteEditorAISuggestion.swift
// AI suggestion functionality for UnifiedNoteEditor - extracted for maintainability

import SwiftUI
import SwiftData

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

// MARK: - AI Suggestion Extension

extension UnifiedNoteEditor {

    @MainActor
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func suggestTagsAndScope() async {
        guard !bodyText.trimmed().isEmpty else { return }
        
        guard SystemLanguageModel.default.isAvailable else {
            switch SystemLanguageModel.default.availability {
            case .unavailable(.appleIntelligenceNotEnabled):
                self.suggestionError = "Please enable Apple Intelligence in Settings to use this feature."
            case .unavailable(.deviceNotEligible):
                self.suggestionError = "This device does not support Apple Intelligence."
            case .unavailable(.modelNotReady):
                self.suggestionError = "Apple Intelligence model is downloading. Please try again later."
            default:
                self.suggestionError = "Apple Intelligence is not available."
            }
            return
        }
        
        isSuggesting = true
        defer { isSuggesting = false }

        let session = LanguageModelSession(
            instructions: AIPrompts.noteClassification
        )
        do {
            let response = try await session.respond(
                to: AIPrompts.classifyNote(bodyText),
                generating: NoteTagSuggestion.self,
                options: .init(temperature: 0.2)
            )
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
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .assetsUnavailable:
                self.suggestionError = "Apple Intelligence model is not available."
                    + " It may be downloading — please try again later."
            case .rateLimited:
                self.suggestionError = "Too many requests. Please wait a moment and try again."
            case .exceededContextWindowSize:
                self.suggestionError = "The note is too long for on-device processing. Try with a shorter note."
            case .unsupportedLanguageOrLocale:
                self.suggestionError = "This language is not supported by Apple Intelligence."
            case .refusal:
                self.suggestionError = "The request could not be processed due to content restrictions."
            default:
                self.suggestionError = error.localizedDescription
            }
        } catch {
            self.suggestionError = error.localizedDescription
        }
    }
}

// MARK: - Suggestion Preview Sheet

struct SuggestionPreviewSheet: View {
    let proposedTags: [String]
    let proposedStudentIDs: [UUID]
    let allStudents: [Student]
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
            .navigationBarTitleDisplayMode(.inline)
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
