// NoteTemplateManagementView.swift
// Manage note templates (built-in and user-created)

import SwiftUI
import SwiftData
import OSLog

struct NoteTemplateManagementView: View {
    private static let logger = Logger.settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NoteTemplate.sortOrder)
    private var templates: [NoteTemplate]

    @State private var showingAddSheet = false
    @State private var editingTemplate: NoteTemplate?
    @State private var previewingTemplate: NoteTemplate?

    private var repository: NoteTemplateRepository {
        NoteTemplateRepository(context: modelContext)
    }

    private var builtInTemplates: [NoteTemplate] {
        templates.filter(\.isBuiltIn)
    }

    private var customTemplates: [NoteTemplate] {
        templates.filter { !$0.isBuiltIn }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SettingsStyle.sectionSpacing) {
                // Built-in templates section
                if !builtInTemplates.isEmpty {
                    VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
                        Text("Built-in Templates")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.secondary)

                        ForEach(builtInTemplates) { template in
                            NoteTemplateCardRow(
                                template: template,
                                isBuiltIn: true,
                                onTap: { previewingTemplate = template },
                                onEdit: nil,
                                onDelete: nil
                            )
                        }

                        Text("Built-in templates cannot be edited or deleted.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Custom templates section
                VStack(alignment: .leading, spacing: SettingsStyle.groupSpacing) {
                    Text("My Templates")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)

                    if customTemplates.isEmpty {
                        HStack {
                            Image(systemName: "doc.badge.plus")
                                .foregroundStyle(.secondary)
                            Text("No custom templates yet")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [5]))
                        )
                    } else {
                        ForEach(customTemplates) { template in
                            NoteTemplateCardRow(
                                template: template,
                                isBuiltIn: false,
                                onTap: { previewingTemplate = template },
                                onEdit: { editingTemplate = template },
                                onDelete: { deleteTemplate(template) }
                            )
                        }
                    }

                    Text("Tap a template to preview. Use the menu to edit or delete.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(SettingsStyle.padding)
        }
        .navigationTitle("Note Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddSheet = true
                } label: {
                    Label("Add Template", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            NoteTemplateEditorSheet(template: nil) {
                // Refresh after adding
            }
        }
        .sheet(item: $editingTemplate) { template in
            NoteTemplateEditorSheet(template: template) {
                // Refresh after editing
            }
        }
        .sheet(item: $previewingTemplate) { template in
            NoteTemplatePreviewSheet(template: template)
        }
    }

    // MARK: - Actions

    private func deleteTemplate(_ template: NoteTemplate) {
        adaptiveWithAnimation {
            do {
                try repository.deleteTemplate(id: template.id)
            } catch {
                Self.logger.warning("Failed to delete note template: \(error, privacy: .public)")
            }
        }
    }

    private func reorderTemplates(from source: IndexSet, to destination: Int) {
        var reordered = customTemplates
        reordered.move(fromOffsets: source, toOffset: destination)
        repository.reorderTemplates(ids: reordered.map(\.id))
    }
}

// MARK: - Note Template Card Row

private struct NoteTemplateCardRow: View {
    let template: NoteTemplate
    let isBuiltIn: Bool
    let onTap: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(template.title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        ForEach(template.tags.prefix(2), id: \.self) { tag in
                            TagBadge(tag: tag, compact: true)
                        }
                    }

                    Text(template.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if isBuiltIn {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if onEdit != nil || onDelete != nil {
                    Menu {
                        if let onEdit {
                            Button {
                                onEdit()
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                        }
                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(SettingsStyle.compactPadding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(SettingsStyle.groupBackgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(SettingsStyle.borderOpacity))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

}

// MARK: - Note Template Preview Sheet

private struct NoteTemplatePreviewSheet: View {
    let template: NoteTemplate
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Tag badges
                    if !template.tags.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(template.tags, id: \.self) { tag in
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

}

// MARK: - Preview

#Preview {
    NavigationStack {
        NoteTemplateManagementView()
    }
    .previewEnvironment()
}
