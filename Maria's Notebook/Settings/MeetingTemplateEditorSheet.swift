// MeetingTemplateEditorSheet.swift
// Create or edit a weekly meeting template

import SwiftUI
import CoreData
import OSLog

struct MeetingTemplateEditorSheet: View {
    private static let logger = Logger.settings
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    let template: CDMeetingTemplate?
    var onSaved: () -> Void

    @State private var nameText: String = ""
    @State private var reflectionPromptText: String = ""
    @State private var focusPromptText: String = ""
    @State private var requestsPromptText: String = ""
    @State private var guideNotesPromptText: String = ""

    private var isEditing: Bool { template != nil }

    init(template: CDMeetingTemplate?, onSaved: @escaping () -> Void) {
        self.template = template
        self.onSaved = onSaved
        if let template {
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
            .inlineNavigationTitle()
            .scrollDismissesKeyboard(.interactively)
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 550)
        #endif
    }

    // MARK: - Helpers

    private var canSave: Bool {
        !nameText.trimmed().isEmpty &&
        !reflectionPromptText.trimmed().isEmpty &&
        !focusPromptText.trimmed().isEmpty &&
        !requestsPromptText.trimmed().isEmpty &&
        !guideNotesPromptText.trimmed().isEmpty
    }

    private func save() {
        let trimmedName = nameText.trimmed()
        let trimmedReflection = reflectionPromptText.trimmed()
        let trimmedFocus = focusPromptText.trimmed()
        let trimmedRequests = requestsPromptText.trimmed()
        let trimmedGuideNotes = guideNotesPromptText.trimmed()

        if let existing = template {
            // Update existing template
            existing.name = trimmedName
            existing.reflectionPrompt = trimmedReflection
            existing.focusPrompt = trimmedFocus
            existing.requestsPrompt = trimmedRequests
            existing.guideNotesPrompt = trimmedGuideNotes
        } else {
            // Create new template
            let customCount: Int
            do {
                let countRequest = NSFetchRequest<CDMeetingTemplate>(entityName: "MeetingTemplate")
                countRequest.predicate = NSPredicate(format: "isBuiltIn == NO")
                customCount = try viewContext.count(for: countRequest)
            } catch {
                Self.logger.warning("Failed to fetch custom template count: \(error, privacy: .public)")
                customCount = 0
            }

            let newTemplate = CDMeetingTemplateEntity(context: viewContext)
            newTemplate.id = UUID()
            newTemplate.name = trimmedName
            newTemplate.reflectionPrompt = trimmedReflection
            newTemplate.focusPrompt = trimmedFocus
            newTemplate.requestsPrompt = trimmedRequests
            newTemplate.guideNotesPrompt = trimmedGuideNotes
            newTemplate.sortOrder = Int64(100 + customCount)
            newTemplate.isActive = false
            newTemplate.isBuiltIn = false
        }

        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save meeting template: \(error, privacy: .public)")
        }
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
