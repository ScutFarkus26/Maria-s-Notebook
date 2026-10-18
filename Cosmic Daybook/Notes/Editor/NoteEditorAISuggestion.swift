// NoteEditorAISuggestion.swift
// AI suggestion functionality for UnifiedNoteEditor - extracted for maintainability

import SwiftUI
import CoreData

// MARK: - Suggested Names

/// Which children the names Suggest Tags read in a note mean.
enum SuggestedStudentMatcher {
    /// A name counts only when exactly one child answers to it: a full name
    /// first, then a short name ("Maya S"), then a first name or nickname.
    /// "Sarah" with two Sarahs names nobody; it used to pick the first Sarah.
    static func studentIDs(for names: [String], among students: [CDStudent]) -> [UUID] {
        var found: [UUID] = []
        for name in names {
            let token = name.folded()
            guard !token.isEmpty, let id = onlyMatch(for: token, among: students) else { continue }
            if !found.contains(id) { found.append(id) }
        }
        return found
    }

    private static func onlyMatch(for token: String, among students: [CDStudent]) -> UUID? {
        let tiers: [(CDStudent) -> Bool] = [
            { ($0.firstName + " " + $0.lastName).folded() == token },
            { $0.shortName.folded() == token },
            { $0.firstName.folded() == token || (($0.nickname ?? "").folded() == token && !token.isEmpty) }
        ]
        for matches in tiers {
            let hits = students.filter(matches)
            if hits.count == 1 { return hits[0].id }
            if hits.count > 1 { return nil }
        }
        return nil
    }
}

#if ENABLE_FOUNDATION_MODELS && canImport(FoundationModels)
import FoundationModels

// MARK: - AI Suggestion Extension

extension UnifiedNoteEditor {

    /// The note's photo, downsampled for AI input — only when the on-device
    /// model can actually look at it. A photo taken on another device is
    /// downloaded first, and the file is read off the main thread.
    func noteImageForAI() async -> CGImage? {
        guard SystemLanguageModel.default.capabilities.contains(.vision),
              let path = imagePath else { return nil }
        return await PhotoStorageService.imageForAI(filename: path)
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

    func suggestTagsAndScope() async {
        guard !bodyText.trimmed().isEmpty || imagePath != nil else { return }

        if let reason = suggestTagsUnavailableReason() {
            self.suggestionError = reason
            return
        }

        isSuggesting = true
        defer { isSuggesting = false }

        let noteImage = await noteImageForAI()
        guard !bodyText.trimmed().isEmpty || noteImage != nil else {
            self.suggestionError = photoNotHereMessage
            return
        }

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
            self.proposedTags = content.suggestedTags.map(Self.suggestedTag(named:))
            self.proposedStudentIDs = SuggestedStudentMatcher.studentIDs(
                for: content.studentIdentifiers, among: students
            )
            self.showingSuggestionSheet = true
        } catch let error as LanguageModelError {
            self.suggestionError = suggestionMessage(for: error)
        } catch {
            self.suggestionError = AppErrorMessages.aiMessage(for: error)
        }
    }

    /// A suggested tag name as a tag string, capitalized, in its category's
    /// color when it names a known category.
    private static func suggestedTag(named tagName: String) -> String {
        let color = TagHelper.colorForNoteCategory(tagName.trimmed().lowercased())
        let displayName = tagName.trimmed().prefix(1).uppercased() + tagName.trimmed().dropFirst()
        return TagHelper.createTag(name: displayName, color: color)
    }

    /// Drafts a 1-2 sentence factual description of the attached photo and
    /// appends it to the note body. Runs fully on-device.
    func describePhotoIntoNote() async {
        guard SystemLanguageModel.default.isAvailable else {
            self.suggestionError = appleIntelligenceUnavailableMessage()
            return
        }
        guard SystemLanguageModel.default.capabilities.contains(.vision), imagePath != nil else {
            self.suggestionError = "Describing photos isn't available on this device."
            return
        }

        isDescribingPhoto = true
        defer { isDescribingPhoto = false }

        guard let noteImage = await noteImageForAI() else {
            self.suggestionError = photoNotHereMessage
            return
        }

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

    /// Why Suggest Tags can't run, or nil when it can. A photo-only note on a
    /// device whose model can't look at photos used to be told the photo
    /// hadn't downloaded, which wasn't the reason (review of the 2026-10-17
    /// fixes, a2 #11).
    private func suggestTagsUnavailableReason() -> String? {
        guard SystemLanguageModel.default.isAvailable else { return appleIntelligenceUnavailableMessage() }
        if bodyText.trimmed().isEmpty, !SystemLanguageModel.default.capabilities.contains(.vision) {
            return Self.needsTextMessage
        }
        return nil
    }

    static let needsTextMessage = "Apple Intelligence on this device can't look at photos. "
        + "Write a few words in the note, then try Suggest Tags again."

    /// The note's photo couldn't be read: usually one taken on another device
    /// that iCloud hasn't brought here yet.
    private var photoNotHereMessage: String {
        "Couldn't open the note's photo. If it was taken on another device, it may still be "
            + "downloading. Try again in a moment."
    }

    private func appleIntelligenceUnavailableMessage() -> String {
        AppleIntelligenceMessages.unavailableMessage(for: SystemLanguageModel.default.availability)
            ?? AppleIntelligenceMessages.notAvailable
    }

    private func suggestionMessage(for error: LanguageModelError) -> String {
        AppleIntelligenceMessages.message(
            for: error, tooLong: "This note is too long for Apple Intelligence. Try a shorter note."
        )
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
        allStudents.first(where: { $0.id == id })?.shortName ?? "Student removed"
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
                HStack { Text("Children:").bold(); Text("No change") }
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
                        Text("Adds:").bold()
                        ForEach(proposedStudentIDs, id: \.self) { id in
                            Text(name(for: id))
                        }
                    }
                } else {
                    HStack { Text("Children:").bold(); Text("No change") }
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
