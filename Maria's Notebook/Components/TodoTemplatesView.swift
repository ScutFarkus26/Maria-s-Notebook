// swiftlint:disable file_length
import OSLog
import SwiftUI
import SwiftData

struct TodoTemplatesView: View {
    private static let logger = Logger.todos
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \TodoTemplate.name) private var templates: [TodoTemplate]
    
    @State private var editingTemplate: TodoTemplate?
    @State private var showingCreateSheet = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if templates.isEmpty {
                    emptyState
                } else {
                    templatesList
                }
            }
            .navigationTitle("Todo Templates")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingCreateSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreateSheet) {
                TodoTemplateEditSheet(template: nil)
            }
            .sheet(item: $editingTemplate) { template in
                TodoTemplateEditSheet(template: template)
            }
        }
    }
    
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text")
                .font(.system(size: 60))
                .foregroundStyle(.secondary.opacity(0.5))
            
            Text("No Templates")
                .font(.title2.bold())
            
            Text("Create reusable templates for common tasks")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                showingCreateSheet = true
            } label: {
                Label("Create Template", systemImage: "plus.circle.fill")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var templatesList: some View {
        List {
            ForEach(templates) { template in
                TemplateRow(template: template) {
                    createTodoFromTemplate(template)
                } onEdit: {
                    editingTemplate = template
                } onDelete: {
                    deleteTemplate(template)
                }
            }
        }
        .listStyle(.plain)
    }
    
    private func createTodoFromTemplate(_ template: TodoTemplate) {
        _ = template.createTodoFromTemplate(context: modelContext)
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("[\(#function)] Failed to save todo from template: \(error)")
        }
        dismiss()
    }
    
    private func deleteTemplate(_ template: TodoTemplate) {
        modelContext.delete(template)
        do {
            try modelContext.save()
        } catch {
            Self.logger.error("[\(#function)] Failed to delete template: \(error)")
        }
    }
}

// MARK: - Template Row

private struct TemplateRow: View {
    let template: TodoTemplate
    let onCreate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(template.name)
                    .font(.headline)
                
                Text(template.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 12) {
                    if template.priority != .none {
                        HStack(spacing: 4) {
                            Image(systemName: template.priority.icon)
                                .font(.caption2)
                            Text(template.priority.rawValue)
                                .font(.caption)
                        }
                        .foregroundStyle(priorityColor(template.priority))
                    }
                    
                    if let estimated = template.defaultEstimatedMinutes, estimated > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.caption2)
                            Text(formatMinutes(estimated))
                                .font(.caption)
                        }
                        .foregroundStyle(.cyan)
                    }
                    
                    if !template.tags.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "tag")
                                .font(.caption2)
                            Text("\(template.tags.count)")
                                .font(.caption)
                        }
                        .foregroundStyle(.purple)
                    }
                    
                    if template.useCount > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.on.doc")
                                .font(.caption2)
                            Text("\(template.useCount)")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Button {
                onCreate()
            } label: {
                Text("Use")
                    .font(.subheadline.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
            
            Button {
                onEdit()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }
    
    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }
    
    private func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        
        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
}

// MARK: - Template Edit Sheet

private struct TodoTemplateEditSheet: View {
    private static let logger = Logger.todos
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Student.firstName) private var studentsRaw: [Student]
    private var students: [Student] { studentsRaw.filter(\.isEnrolled) }
    
    let template: TodoTemplate?
    
    @State private var name: String
    @State private var title: String
    @State private var notes: String
    @State private var priority: TodoPriority
    @State private var estimatedHours: Int
    @State private var estimatedMinutes: Int
    @State private var selectedStudentIDs: Set<String>
    @State private var selectedTags: [String]
    @State private var isShowingTagPicker = false
    
    init(template: TodoTemplate?) {
        self.template = template
        _name = State(initialValue: template?.name ?? "")
        _title = State(initialValue: template?.title ?? "")
        _notes = State(initialValue: template?.notes ?? "")
        _priority = State(initialValue: template?.priority ?? .none)
        
        let estTotal = template?.defaultEstimatedMinutes ?? 0
        _estimatedHours = State(initialValue: estTotal / 60)
        _estimatedMinutes = State(initialValue: estTotal % 60)
        _selectedStudentIDs = State(initialValue: Set(template?.defaultStudentIDs ?? []))
        _selectedTags = State(initialValue: template?.tags ?? [])
    }
    
    private var canSave: Bool {
        !name.trimmed().isEmpty &&
        !title.trimmed().isEmpty
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Template Name") {
                    TextField("e.g., Weekly Lesson Plan", text: $name)
                }
                
                Section("Default Todo Title") {
                    TextField("Task title", text: $title)
                }
                
                Section("Priority") {
                    Picker("Priority", selection: $priority) {
                        ForEach(TodoPriority.allCases, id: \.self) { priority in
                            Text(priority.rawValue).tag(priority)
                        }
                    }
                }
                
                estimatedTimeSection
                
                if !students.isEmpty {
                    studentsSection
                }
                
                tagsSection
                
                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 100)
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isShowingTagPicker) {
                TagPicker(selectedTags: $selectedTags)
            }
        }
    }
    
    private var estimatedTimeSection: some View {
        Section("Estimated Time") {
            HStack {
                Picker("Hours", selection: $estimatedHours) {
                    ForEach(0..<24, id: \.self) { hour in
                        Text("\(hour) hr").tag(hour)
                    }
                }
                
                Picker("Minutes", selection: $estimatedMinutes) {
                    ForEach([0, 15, 30, 45], id: \.self) { minute in
                        Text("\(minute) min").tag(minute)
                    }
                }
            }
        }
    }
    
    private var studentsSection: some View {
        Section("Default Students") {
            ForEach(students) { student in
                Button {
                    if selectedStudentIDs.contains(student.id.uuidString) {
                        selectedStudentIDs.remove(student.id.uuidString)
                    } else {
                        selectedStudentIDs.insert(student.id.uuidString)
                    }
                } label: {
                    HStack {
                        Text("\(student.firstName) \(student.lastName)")
                            .foregroundStyle(.primary)
                        Spacer()
                        if selectedStudentIDs.contains(student.id.uuidString) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                        }
                    }
                }
            }
        }
    }
    
    private var tagsSection: some View {
        Section("Tags") {
            if selectedTags.isEmpty {
                Text("No tags")
                    .foregroundStyle(.secondary)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(selectedTags, id: \.self) { tag in
                        templateTagBadge(tag)
                    }
                }
            }
            
            Button {
                isShowingTagPicker = true
            } label: {
                Label("Edit Tags", systemImage: "tag")
            }
        }
    }
    
    private func templateTagBadge(_ tag: String) -> some View {
        HStack(spacing: 4) {
            Text(TodoTagHelper.tagName(tag))
                .font(AppTheme.ScaledFont.captionSemibold)
            Button {
                selectedTags.removeAll { $0 == tag }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(TodoTagHelper.tagColor(tag).lightColor)
        .foregroundStyle(TodoTagHelper.tagColor(tag).color)
        .clipShape(Capsule())
    }
    
    private func save() {
        let trimmedName = name.trimmed()
        let trimmedTitle = title.trimmed()
        let trimmedNotes = notes.trimmed()
        
        let totalEstimated = estimatedHours * 60 + estimatedMinutes
        
        if let existing = template {
            // Update existing template
            existing.name = trimmedName
            existing.title = trimmedTitle
            existing.notes = trimmedNotes
            existing.priority = priority
            existing.defaultEstimatedMinutes = totalEstimated > 0 ? totalEstimated : nil
            existing.defaultStudentIDs = Array(selectedStudentIDs)
            existing.tags = selectedTags
        } else {
            // Create new template
            let newTemplate = TodoTemplate(
                name: trimmedName,
                title: trimmedTitle,
                notes: trimmedNotes,
                priority: priority,
                defaultEstimatedMinutes: totalEstimated > 0 ? totalEstimated : nil,
                defaultStudentIDs: Array(selectedStudentIDs),
                tags: selectedTags
            )
            modelContext.insert(newTemplate)
        }

        do {
            try modelContext.save()
        } catch {
            Self.logger.error("[\(#function)] Failed to save template: \(error)")
        }
        dismiss()
    }
}
