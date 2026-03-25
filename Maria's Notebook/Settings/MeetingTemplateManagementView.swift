// MeetingTemplateManagementView.swift
// Manage weekly meeting templates (built-in and user-created)

import SwiftUI
import SwiftData
import OSLog

struct MeetingTemplateManagementView: View {
    private static let logger = Logger.settings
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingTemplate.sortOrder)
    private var templates: [MeetingTemplate]

    @State private var showingAddSheet = false
    @State private var editingTemplate: MeetingTemplate?
    @State private var previewingTemplate: MeetingTemplate?

    private var repository: MeetingTemplateRepository {
        MeetingTemplateRepository(context: modelContext)
    }

    private var builtInTemplates: [MeetingTemplate] {
        templates.filter(\.isBuiltIn)
    }

    private var customTemplates: [MeetingTemplate] {
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
                            MeetingTemplateCardRow(
                                template: template,
                                isBuiltIn: true,
                                onTap: { previewingTemplate = template },
                                onActivate: { activateTemplate(template) },
                                onEdit: nil,
                                onDelete: nil
                            )
                        }

                        Text("Built-in templates cannot be edited or deleted, but can be set as active.")
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
                            MeetingTemplateCardRow(
                                template: template,
                                isBuiltIn: false,
                                onTap: { previewingTemplate = template },
                                onActivate: { activateTemplate(template) },
                                onEdit: { editingTemplate = template },
                                onDelete: { deleteTemplate(template) }
                            )
                        }
                    }

                    Text("Tap a template to preview. The active template's prompts are shown in weekly meetings.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(SettingsStyle.padding)
        }
        .navigationTitle("Meeting Templates")
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
            MeetingTemplateEditorSheet(template: nil) {
                // Refresh after adding
            }
        }
        .sheet(item: $editingTemplate) { template in
            MeetingTemplateEditorSheet(template: template) {
                // Refresh after editing
            }
        }
        .sheet(item: $previewingTemplate) { template in
            MeetingTemplatePreviewSheet(template: template, onActivate: {
                activateTemplate(template)
            })
        }
        .onAppear {
            // Seed built-in templates if needed
            MeetingTemplate.seedBuiltInTemplates(in: modelContext)
        }
    }

    // MARK: - Actions

    private func activateTemplate(_ template: MeetingTemplate) {
        adaptiveWithAnimation {
            repository.setActiveTemplate(id: template.id)
        }
    }

    private func deleteTemplate(_ template: MeetingTemplate) {
        adaptiveWithAnimation {
            do {
                try repository.deleteTemplate(id: template.id)
            } catch {
                Self.logger.warning("Failed to delete meeting template: \(error, privacy: .public)")
            }
        }
    }

    private func reorderTemplates(from source: IndexSet, to destination: Int) {
        var reordered = customTemplates
        reordered.move(fromOffsets: source, toOffset: destination)
        repository.reorderTemplates(ids: reordered.map(\.id))
    }
}

// MARK: - Meeting Template Card Row

private struct MeetingTemplateCardRow: View {
    let template: MeetingTemplate
    let isBuiltIn: Bool
    let onTap: () -> Void
    let onActivate: () -> Void
    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Active indicator
                Circle()
                    .fill(template.isActive ? Color.green : Color.secondary.opacity(0.3))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(template.name)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if template.isActive {
                            Text("Active")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(AppColors.success.opacity(0.15)))
                                .foregroundStyle(AppColors.success)
                        }
                    }

                    Text(template.reflectionPrompt)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isBuiltIn {
                    Image(systemName: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Menu {
                    if !template.isActive {
                        Button {
                            onActivate()
                        } label: {
                            Label("Set as Active", systemImage: "checkmark.circle")
                        }
                    }
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
                    .stroke(
                        template.isActive
                            ? AppColors.success.opacity(0.3)
                            : Color.primary.opacity(SettingsStyle.borderOpacity)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Meeting Template Preview Sheet

private struct MeetingTemplatePreviewSheet: View {
    let template: MeetingTemplate
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
                                .background(Capsule().fill(AppColors.success.opacity(0.15)))
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
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
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

#Preview {
    NavigationStack {
        MeetingTemplateManagementView()
    }
    .previewEnvironment()
}
