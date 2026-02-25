// NoteTemplateEditorSheet.swift
// Create or edit a note template

import SwiftUI
import SwiftData
import OSLog

struct NoteTemplateEditorSheet: View {
    private static let logger = Logger.settings
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let template: NoteTemplate?
    var onSaved: () -> Void

    @State private var titleText: String = ""
    @State private var bodyText: String = ""
    @State private var tags: [String] = []
    @State private var showingTagPicker: Bool = false

    private var isEditing: Bool { template != nil }

    init(template: NoteTemplate?, onSaved: @escaping () -> Void) {
        self.template = template
        self.onSaved = onSaved
        if let template = template {
            _titleText = State(initialValue: template.title)
            _bodyText = State(initialValue: template.body)
            _tags = State(initialValue: template.tags)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $titleText, prompt: Text("e.g., Completed independently"))
                        #if os(iOS)
                        .textInputAutocapitalization(.sentences)
                        #endif
                } header: {
                    Text("Title")
                } footer: {
                    Text("Short text shown as a quick-insert button")
                }

                Section {
                    TextEditor(text: $bodyText)
                        .frame(minHeight: 120)
                } header: {
                    Text("Template Text")
                } footer: {
                    Text("Full text that will be inserted into the note")
                }

                Section {
                    FlowLayout(spacing: 4) {
                        ForEach(tags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                TagBadge(tag: tag, compact: true)
                                Button {
                                    tags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        Button {
                            showingTagPicker = true
                        } label: {
                            Label("Add Tag", systemImage: "plus.circle")
                                .font(.caption)
                        }
                    }
                    .sheet(isPresented: $showingTagPicker) {
                        NoteTagPickerSheet(selectedTags: $tags)
                        #if os(iOS)
                            .presentationDetents([.medium, .large])
                        #else
                            .frame(minWidth: 400, minHeight: 400)
                        #endif
                    }
                } header: {
                    Text("Default Tags")
                } footer: {
                    Text("Tags to auto-select when using this template")
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
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 400)
        #endif
    }

    // MARK: - Helpers

    private var canSave: Bool {
        !titleText.trimmed().isEmpty &&
        !bodyText.trimmed().isEmpty
    }

    private func save() {
        let trimmedTitle = titleText.trimmed()
        let trimmedBody = bodyText.trimmed()

        if let existing = template {
            // Update existing template
            existing.title = trimmedTitle
            existing.body = trimmedBody
            existing.tags = tags
        } else {
            // Create new template
            // Get the next sort order for custom templates
            let customCount: Int
            do {
                customCount = try modelContext.fetchCount(
                    FetchDescriptor<NoteTemplate>(
                        predicate: #Predicate<NoteTemplate> { !$0.isBuiltIn }
                    )
                )
            } catch {
                Self.logger.warning("Failed to fetch custom template count: \(error, privacy: .public)")
                customCount = 0
            }

            let newTemplate = NoteTemplate(
                title: trimmedTitle,
                body: trimmedBody,
                tags: tags,
                sortOrder: 100 + customCount, // Custom templates start at 100
                isBuiltIn: false
            )
            modelContext.insert(newTemplate)
        }

        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save note template: \(error, privacy: .public)")
        }
        onSaved()
        dismiss()
    }

}

// MARK: - Preview

#Preview {
    NoteTemplateEditorSheet(template: nil) {
        print("Saved!")
    }
}
