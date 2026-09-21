// NoteTemplateManagementView.swift
// Manage note templates (built-in and user-created)

import SwiftUI
import CoreData
import OSLog

/// Drives the shared template-management screen for note templates.
enum NoteTemplateManaging: TemplateManaging {
    private static let logger = Logger.settings

    static var sortDescriptors: [NSSortDescriptor] {
        [NSSortDescriptor(keyPath: \CDNoteTemplate.sortOrder, ascending: true)]
    }

    static let navigationTitle = "Note Templates"
    static let builtInFooter = "Built-in templates cannot be edited or deleted."
    static var customFooter: String {
        "\(PlatformVerb.tap) a template to preview. Use the menu to edit or delete."
    }
    static let subtitleLineLimit = 2

    static func isBuiltIn(_ template: CDNoteTemplate) -> Bool { template.isBuiltIn }
    static func title(of template: CDNoteTemplate) -> String { template.title }
    static func subtitle(of template: CDNoteTemplate) -> String { template.body }
    static func tags(of template: CDNoteTemplate) -> [String] { (template.tags as? [String]) ?? [] }

    static func delete(_ template: CDNoteTemplate, in context: NSManagedObjectContext) {
        guard let id = template.id else { return }
        do {
            try NoteTemplateRepository(context: context).deleteTemplate(id: id)
        } catch {
            logger.warning("Failed to delete note template: \(error, privacy: .public)")
        }
    }

    static func editorSheet(for template: CDNoteTemplate?) -> some View {
        NoteTemplateEditorSheet(template: template) {
            // Refresh after adding or editing
        }
    }

    static func previewSheet(
        for template: CDNoteTemplate,
        onActivate _: @escaping () -> Void
    ) -> some View {
        NoteTemplatePreviewSheet(template: template)
    }
}

typealias NoteTemplateManagementView = TemplateManagementView<NoteTemplateManaging>

// MARK: - CDNote Template Preview Sheet

private struct NoteTemplatePreviewSheet: View {
    let template: CDNoteTemplate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Tag badges
                    if !((template.tags as? [String]) ?? []).isEmpty {
                        HStack(spacing: 6) {
                            ForEach((template.tags as? [String]) ?? [], id: \.self) { tag in
                                TagBadge(tag: tag)
                            }
                            Spacer()
                        }
                    }

                    // Template content
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Template Content")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)

                        Text(template.body)
                            .font(.body)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(SettingsStyle.groupBackgroundColor)
                            )
                    }
                }
                .padding()
            }
            .navigationTitle(template.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct NoteTemplateManagementViewPreview: View {
    var body: some View {
        NavigationStack {
            NoteTemplateManagementView()
        }
        .previewEnvironment()
    }
}

#Preview {
    NoteTemplateManagementViewPreview()
}
