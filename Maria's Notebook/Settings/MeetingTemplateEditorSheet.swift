// MeetingTemplateEditorSheet.swift
// Create or edit a weekly meeting template

import SwiftUI
import SwiftData

struct MeetingTemplateEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let template: MeetingTemplate?
    var onSaved: () -> Void

    @State private var nameText: String = ""
    @State private var reflectionPromptText: String = ""
    @State private var focusPromptText: String = ""
    @State private var requestsPromptText: String = ""
    @State private var guideNotesPromptText: String = ""

    private var isEditing: Bool { template != nil }

    init(template: MeetingTemplate?, onSaved: @escaping () -> Void) {
        self.template = template
        self.onSaved = onSaved
        if let template = template {
            _nameText = State(initialValue: template.name)
            _reflectionPromptText = State(initialValue: template.reflectionPrompt)
            _focusPromptText = State(initialValue: template.focusPrompt)
            _requestsPromptText = State(initialValue: template.requestsPrompt)
            _guideNotesPromptText = State(initialValue: template.guideNotesPrompt)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $nameText, prompt: Text("e.g., Weekly Check-in"))
                        #if os(iOS)
                        .textInputAutocapitalization(.words)
                        #endif
                } header: {
                    Text("Template Name")
                } footer: {
                    Text("A descriptive name for this template")
                }

                Section {
                    TextEditor(text: $reflectionPromptText)
                        .frame(minHeight: 60)
                } header: {
                    Text("Reflection Prompt")
                } footer: {
                    Text("Placeholder shown in the student reflection field")
                }

                Section {
                    TextEditor(text: $focusPromptText)
                        .frame(minHeight: 60)
                } header: {
                    Text("Focus Prompt")
                } footer: {
                    Text("Placeholder shown in the focus/goals field")
                }

                Section {
                    TextEditor(text: $requestsPromptText)
                        .frame(minHeight: 60)
                } header: {
                    Text("Requests Prompt")
                } footer: {
                    Text("Placeholder shown in the lesson requests field")
                }

                Section {
                    TextEditor(text: $guideNotesPromptText)
                        .frame(minHeight: 60)
                } header: {
                    Text("Guide Notes Prompt")
                } footer: {
                    Text("Placeholder shown in the private guide notes field")
                }
            }
            .navigationTitle(isEditing ? "Edit Template" : "New Template")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 550)
        #endif
    }

    // MARK: - Helpers

    private var canSave: Bool {
        !nameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !reflectionPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !focusPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !requestsPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !guideNotesPromptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmedName = nameText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReflection = reflectionPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFocus = focusPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRequests = requestsPromptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGuideNotes = guideNotesPromptText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let existing = template {
            // Update existing template
            existing.name = trimmedName
            existing.reflectionPrompt = trimmedReflection
            existing.focusPrompt = trimmedFocus
            existing.requestsPrompt = trimmedRequests
            existing.guideNotesPrompt = trimmedGuideNotes
        } else {
            // Create new template
            let customCount = (try? modelContext.fetchCount(
                FetchDescriptor<MeetingTemplate>(
                    predicate: #Predicate<MeetingTemplate> { !$0.isBuiltIn }
                )
            )) ?? 0

            let newTemplate = MeetingTemplate(
                name: trimmedName,
                reflectionPrompt: trimmedReflection,
                focusPrompt: trimmedFocus,
                requestsPrompt: trimmedRequests,
                guideNotesPrompt: trimmedGuideNotes,
                sortOrder: 100 + customCount,
                isActive: false,
                isBuiltIn: false
            )
            modelContext.insert(newTemplate)
        }

        try? modelContext.save()
        onSaved()
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    MeetingTemplateEditorSheet(template: nil) {
        print("Saved!")
    }
}
