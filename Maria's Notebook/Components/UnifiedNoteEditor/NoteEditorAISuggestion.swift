// NoteEditorAISuggestion.swift
// AI suggestion functionality for UnifiedNoteEditor - extracted for maintainability

import SwiftUI
import SwiftData

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

// MARK: - AI Suggestion Extension

extension UnifiedNoteEditor {

    @MainActor
    func suggestCategoryAndScope() async {
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
                generating: NoteClassificationSuggestion.self,
                options: .init(temperature: 0.2)
            )
            let content = response.content

            let proposedCat = NoteCategory(rawValue: content.category.lowercased()) ?? .general

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

            self.proposedCategory = proposedCat
            self.proposedStudentIDs = Array(Set(ids))
            self.showingSuggestionSheet = true
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .assetsUnavailable:
                self.suggestionError = "Apple Intelligence model is not available. It may be downloading — please try again later."
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
    let proposedCategory: NoteCategory?
    let proposedStudentIDs: [UUID]
    let allStudents: [Student]
    let onApply: () -> Void
    let onCancel: () -> Void

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
            Text("Suggested Classification")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            if let cat = proposedCategory {
                HStack {
                    Text("Category:").bold()
                    Text(cat.rawValue.capitalized)
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
                Button("Apply") { onApply() }.buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(minWidth: 420)
        .presentationSizingFitted()
        #else
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                if let cat = proposedCategory {
                    HStack {
                        Text("Category:").bold()
                        Text(cat.rawValue.capitalized)
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
            .navigationTitle("Suggested Classification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onCancel() } }
                ToolbarItem(placement: .confirmationAction) { Button("Apply") { onApply() } }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        #endif
    }
}
#endif
