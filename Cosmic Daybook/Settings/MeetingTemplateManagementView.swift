// MeetingTemplateManagementView.swift
// Manage weekly meeting templates (built-in and user-created)

import SwiftUI
import CoreData
import OSLog

/// Drives the shared template-management screen for weekly meeting templates.
enum MeetingTemplateManaging: TemplateManaging {
    private static let logger = Logger.settings

    static var sortDescriptors: [NSSortDescriptor] {
        [NSSortDescriptor(keyPath: \CDMeetingTemplate.sortOrder, ascending: true)]
    }

    static let navigationTitle = "Meeting Templates"
    static let builtInFooter = "Built-in templates cannot be edited or deleted, but can be set as active."
    static var customFooter: String {
        "\(PlatformVerb.tap) a template to preview. "
            + "The active template's prompts are shown in weekly meetings."
    }
    static let supportsActivation = true

    static func isBuiltIn(_ template: CDMeetingTemplate) -> Bool { template.isBuiltIn }
    static func isActive(_ template: CDMeetingTemplate) -> Bool { template.isActive }
    static func title(of template: CDMeetingTemplate) -> String { template.name }
    static func subtitle(of template: CDMeetingTemplate) -> String { template.reflectionPrompt }

    static func seedIfNeeded(in context: NSManagedObjectContext) {
        BuiltInTemplateSeeder.seedIfNeeded(context: context)
    }

    static func activate(_ template: CDMeetingTemplate, in context: NSManagedObjectContext) {
        if let templateID = template.id {
            MeetingTemplateRepository(context: context).setActiveTemplate(id: templateID)
        }
    }

    static func delete(_ template: CDMeetingTemplate, in context: NSManagedObjectContext) {
        do {
            if let templateID = template.id {
                try MeetingTemplateRepository(context: context).deleteTemplate(id: templateID)
            }
        } catch {
            logger.warning("Failed to delete meeting template: \(error, privacy: .public)")
        }
    }

    static func editorSheet(for template: CDMeetingTemplate?) -> some View {
        MeetingTemplateEditorSheet(template: template) {
            // Refresh after adding or editing
        }
    }

    static func previewSheet(
        for template: CDMeetingTemplate,
        onActivate: @escaping () -> Void
    ) -> some View {
        MeetingTemplatePreviewSheet(template: template, onActivate: onActivate)
    }
}

typealias MeetingTemplateManagementView = TemplateManagementView<MeetingTemplateManaging>

// MARK: - Meeting Template Preview Sheet

private struct MeetingTemplatePreviewSheet: View {
    let template: CDMeetingTemplate
    let onActivate: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Status badge
                    HStack {
                        if template.isActive {
                            Label("Active Template", systemImage: "checkmark.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(
                                    Capsule().fill(AppColors.success.opacity(UIConstants.OpacityConstants.accent))
                                )
                                .foregroundStyle(AppColors.success)
                        }
                        Spacer()
                    }

                    // Prompts
                    PromptSection(
                        title: "Reflection Prompt",
                        icon: "bubble.left.and.bubble.right",
                        content: template.reflectionPrompt
                    )
                    PromptSection(title: "Focus Prompt", icon: "target", content: template.focusPrompt)
                    PromptSection(title: "Requests Prompt", icon: "hand.raised", content: template.requestsPrompt)
                    PromptSection(title: "Guide Notes Prompt", icon: "note.text", content: template.guideNotesPrompt)
                }
                .padding()
            }
            .navigationTitle(template.name)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !template.isActive {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Set as Active") {
                            onActivate()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

private struct PromptSection: View {
    let title: String
    let icon: String
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.secondary)

            Text(content)
                .font(.body)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(SettingsStyle.groupBackgroundColor)
                )
        }
    }
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct MeetingTemplateManagementViewPreview: View {
    var body: some View {
        NavigationStack {
            MeetingTemplateManagementView()
        }
        .previewEnvironment()
    }
}

#Preview {
    MeetingTemplateManagementViewPreview()
}
