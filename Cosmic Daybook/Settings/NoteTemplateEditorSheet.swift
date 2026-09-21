// NoteTemplateEditorSheet.swift
// Create or edit a note template

import SwiftUI
import CoreData

/// The editable copy of a note template's fields.
struct NoteTemplateDraft {
    var title = ""
    var body = ""
    var tags: [String] = []
}

/// Drives the shared template editor sheet for note templates.
enum NoteTemplateEditing: TemplateEditing {
    static let macOSMinSize = CGSize(width: 450, height: 400)

    static func makeDraft(from template: CDNoteTemplate?) -> NoteTemplateDraft {
        guard let template else { return NoteTemplateDraft() }
        return NoteTemplateDraft(
            title: template.title,
            body: template.body,
            tags: (template.tags as? [String]) ?? []
        )
    }

    static func canSave(_ draft: NoteTemplateDraft) -> Bool {
        !draft.title.trimmed().isEmpty &&
        !draft.body.trimmed().isEmpty
    }

    @ViewBuilder
    static func fields(_ draft: Binding<NoteTemplateDraft>) -> some View {
        Section {
            TextField("Title", text: draft.title, prompt: Text("e.g., Completed independently"))
                #if os(iOS)
                .textInputAutocapitalization(.sentences)
                #endif
        } header: {
            Text("Title")
        } footer: {
            Text("Short text shown as a quick-insert button")
        }

        Section {
            TextEditor(text: draft.body)
                .frame(minHeight: 120)
        } header: {
            Text("Template Text")
        } footer: {
            Text("Full text that will be inserted into the note")
        }

        Section {
            NoteTemplateTagsField(tags: draft.tags)
        } header: {
            Text("Default Tags")
        } footer: {
            Text("Tags to auto-select when using this template")
        }
    }

    static func apply(_ draft: NoteTemplateDraft, to template: CDNoteTemplate) {
        template.title = draft.title.trimmed()
        template.body = draft.body.trimmed()
        template.tags = draft.tags as NSObject
    }

    static func insert(
        _ draft: NoteTemplateDraft,
        sortOrder: Int64,
        into context: NSManagedObjectContext
    ) {
        let newTemplate = CDNoteTemplate(context: context)
        apply(draft, to: newTemplate)
        newTemplate.sortOrder = sortOrder // Custom templates start at 100
        newTemplate.isBuiltIn = false
    }
}

typealias NoteTemplateEditorSheet = TemplateEditorSheet<NoteTemplateEditing>

// MARK: - Default Tags Field

private struct NoteTemplateTagsField: View {
    @Binding var tags: [String]
    @State private var showingTagPicker = false

    var body: some View {
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
    }
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct NoteTemplateEditorSheetPreview: View {
    var body: some View {
        NoteTemplateEditorSheet(template: nil) {
            print("Saved!")
        }
    }
}

#Preview {
    NoteTemplateEditorSheetPreview()
}
