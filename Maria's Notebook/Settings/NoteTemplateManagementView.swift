// NoteTemplateManagementView.swift
// Manage note templates (built-in and user-created)

import SwiftUI
import SwiftData

struct NoteTemplateManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \NoteTemplate.sortOrder)
    private var templates: [NoteTemplate]

    @State private var showingAddSheet = false
    @State private var editingTemplate: NoteTemplate?

    private var repository: NoteTemplateRepository {
        NoteTemplateRepository(context: modelContext)
    }

    private var builtInTemplates: [NoteTemplate] {
        templates.filter { $0.isBuiltIn }
    }

    private var customTemplates: [NoteTemplate] {
        templates.filter { !$0.isBuiltIn }
    }

    var body: some View {
        List {
            // Built-in templates section
            if !builtInTemplates.isEmpty {
                Section {
                    ForEach(builtInTemplates) { template in
                        TemplateRow(template: template, isBuiltIn: true)
                    }
                } header: {
                    Text("Built-in Templates")
                } footer: {
                    Text("Built-in templates cannot be edited or deleted.")
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
                        TemplateRow(template: template, isBuiltIn: false)
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
                Text("Tap a template to preview. Swipe to edit or delete.")
            }
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
            #if os(iOS)
            ToolbarItem(placement: .automatic) {
                EditButton()
            }
            #endif
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
    }

    // MARK: - Actions

    private func deleteTemplate(_ template: NoteTemplate) {
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

private struct TemplateRow: View {
    let template: NoteTemplate
    let isBuiltIn: Bool

    @State private var showingPreview = false

    var body: some View {
        Button {
            showingPreview = true
        } label: {
            HStack(spacing: 12) {
                // Category color indicator
                Circle()
                    .fill(categoryColor(for: template.category))
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(template.title)
                        .font(.headline)
                        .foregroundStyle(.primary)

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
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert("Template Preview", isPresented: $showingPreview) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("\(template.title)\n\n\(template.body)\n\nCategory: \(template.category.rawValue.capitalized)")
        }
    }

    private func categoryColor(for category: NoteCategory) -> Color {
        switch category {
        case .academic: return .blue
        case .behavioral: return .orange
        case .social: return .purple
        case .emotional: return .pink
        case .health: return .green
        case .attendance: return .teal
        case .general: return .gray
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
