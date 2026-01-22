// MeetingTemplateManagementView.swift
// Manage weekly meeting templates (built-in and user-created)

import SwiftUI
import SwiftData

struct MeetingTemplateManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MeetingTemplate.sortOrder)
    private var templates: [MeetingTemplate]

    @State private var showingAddSheet = false
    @State private var editingTemplate: MeetingTemplate?

    private var repository: MeetingTemplateRepository {
        MeetingTemplateRepository(context: modelContext)
    }

    private var builtInTemplates: [MeetingTemplate] {
        templates.filter { $0.isBuiltIn }
    }

    private var customTemplates: [MeetingTemplate] {
        templates.filter { !$0.isBuiltIn }
    }

    var body: some View {
        List {
            // Built-in templates section
            if !builtInTemplates.isEmpty {
                Section {
                    ForEach(builtInTemplates) { template in
                        MeetingTemplateRow(
                            template: template,
                            isBuiltIn: true,
                            onActivate: { activateTemplate(template) }
                        )
                    }
                } header: {
                    Text("Built-in Templates")
                } footer: {
                    Text("Built-in templates cannot be edited or deleted, but can be set as active.")
                }
            }

            // Custom templates section
            Section {
                if customTemplates.isEmpty {
                    Text("No custom templates yet")
                        .foregroundStyle(.secondary)
                        .italic()
                } else {
                    ForEach(customTemplates) { template in
                        MeetingTemplateRow(
                            template: template,
                            isBuiltIn: false,
                            onActivate: { activateTemplate(template) }
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteTemplate(template)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                editingTemplate = template
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .contextMenu {
                            Button {
                                activateTemplate(template)
                            } label: {
                                Label("Set as Active", systemImage: "checkmark.circle")
                            }
                            .disabled(template.isActive)

                            Button {
                                editingTemplate = template
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }

                            Button(role: .destructive) {
                                deleteTemplate(template)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: reorderTemplates)
                }
            } header: {
                Text("My Templates")
            } footer: {
                Text("Tap a template to preview. Swipe to edit or delete. The active template's prompts are shown in weekly meetings.")
            }
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
            #if os(iOS)
            ToolbarItem(placement: .automatic) {
                EditButton()
            }
            #endif
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
        .onAppear {
            // Seed built-in templates if needed
            MeetingTemplate.seedBuiltInTemplates(in: modelContext)
        }
    }

    // MARK: - Actions

    private func activateTemplate(_ template: MeetingTemplate) {
        withAnimation {
            repository.setActiveTemplate(id: template.id)
        }
    }

    private func deleteTemplate(_ template: MeetingTemplate) {
        withAnimation {
            try? repository.deleteTemplate(id: template.id)
        }
    }

    private func reorderTemplates(from source: IndexSet, to destination: Int) {
        var reordered = customTemplates
        reordered.move(fromOffsets: source, toOffset: destination)
        repository.reorderTemplates(ids: reordered.map { $0.id })
    }
}

// MARK: - Template Row

private struct MeetingTemplateRow: View {
    let template: MeetingTemplate
    let isBuiltIn: Bool
    let onActivate: () -> Void

    @State private var showingPreview = false

    var body: some View {
        Button {
            showingPreview = true
        } label: {
            HStack(spacing: 12) {
                // Active indicator
                if template.isActive {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title3)
                } else {
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

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
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("Template Preview", isPresented: $showingPreview) {
            if !template.isActive {
                Button("Set as Active") {
                    onActivate()
                }
            }
            Button("OK", role: .cancel) { }
        } message: {
            Text("""
            \(template.name)\(template.isActive ? " (Active)" : "")

            Reflection: \(template.reflectionPrompt)

            Focus: \(template.focusPrompt)

            Requests: \(template.requestsPrompt)

            Guide Notes: \(template.guideNotesPrompt)
            """)
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
