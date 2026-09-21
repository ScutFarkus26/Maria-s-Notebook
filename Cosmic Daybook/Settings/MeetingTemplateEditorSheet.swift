// MeetingTemplateEditorSheet.swift
// Create or edit a weekly meeting template

import SwiftUI
import CoreData

/// The editable copy of a meeting template's fields.
struct MeetingTemplateDraft {
    var name = ""
    var reflectionPrompt = ""
    var focusPrompt = ""
    var requestsPrompt = ""
    var guideNotesPrompt = ""
}

/// Drives the shared template editor sheet for weekly meeting templates.
enum MeetingTemplateEditing: TemplateEditing {
    static let macOSMinSize = CGSize(width: 500, height: 550)
    static var keyboardDismissMode: ScrollDismissesKeyboardMode { .interactively }

    static func makeDraft(from template: CDMeetingTemplate?) -> MeetingTemplateDraft {
        guard let template else { return MeetingTemplateDraft() }
        return MeetingTemplateDraft(
            name: template.name,
            reflectionPrompt: template.reflectionPrompt,
            focusPrompt: template.focusPrompt,
            requestsPrompt: template.requestsPrompt,
            guideNotesPrompt: template.guideNotesPrompt
        )
    }

    static func canSave(_ draft: MeetingTemplateDraft) -> Bool {
        !draft.name.trimmed().isEmpty &&
        !draft.reflectionPrompt.trimmed().isEmpty &&
        !draft.focusPrompt.trimmed().isEmpty &&
        !draft.requestsPrompt.trimmed().isEmpty &&
        !draft.guideNotesPrompt.trimmed().isEmpty
    }

    @ViewBuilder
    static func fields(_ draft: Binding<MeetingTemplateDraft>) -> some View {
        Section {
            TextField("Name", text: draft.name, prompt: Text("e.g., Weekly Check-in"))
                #if os(iOS)
                .textInputAutocapitalization(.words)
                #endif
        } header: {
            Text("Template Name")
        } footer: {
            Text("A descriptive name for this template")
        }

        Section {
            TextEditor(text: draft.reflectionPrompt)
                .frame(minHeight: 60)
        } header: {
            Text("Reflection Prompt")
        } footer: {
            Text("Placeholder shown in the student reflection field")
        }

        Section {
            TextEditor(text: draft.focusPrompt)
                .frame(minHeight: 60)
        } header: {
            Text("Focus Prompt")
        } footer: {
            Text("Placeholder shown in the focus/goals field")
        }

        Section {
            TextEditor(text: draft.requestsPrompt)
                .frame(minHeight: 60)
        } header: {
            Text("Requests Prompt")
        } footer: {
            Text("Placeholder shown in the lesson requests field")
        }

        Section {
            TextEditor(text: draft.guideNotesPrompt)
                .frame(minHeight: 60)
        } header: {
            Text("Guide Notes Prompt")
        } footer: {
            Text("Placeholder shown in the private guide notes field")
        }
    }

    static func apply(_ draft: MeetingTemplateDraft, to template: CDMeetingTemplate) {
        template.name = draft.name.trimmed()
        template.reflectionPrompt = draft.reflectionPrompt.trimmed()
        template.focusPrompt = draft.focusPrompt.trimmed()
        template.requestsPrompt = draft.requestsPrompt.trimmed()
        template.guideNotesPrompt = draft.guideNotesPrompt.trimmed()
    }

    static func insert(
        _ draft: MeetingTemplateDraft,
        sortOrder: Int64,
        into context: NSManagedObjectContext
    ) {
        let newTemplate = CDMeetingTemplate(context: context)
        newTemplate.id = UUID()
        apply(draft, to: newTemplate)
        newTemplate.sortOrder = sortOrder
        newTemplate.isActive = false
        newTemplate.isBuiltIn = false
    }
}

typealias MeetingTemplateEditorSheet = TemplateEditorSheet<MeetingTemplateEditing>

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct MeetingTemplateEditorSheetPreview: View {
    var body: some View {
        MeetingTemplateEditorSheet(template: nil) {
            print("Saved!")
        }
    }
}

#Preview {
    MeetingTemplateEditorSheetPreview()
}
