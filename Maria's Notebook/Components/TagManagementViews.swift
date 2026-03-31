// TagManagementViews.swift
// Elegant full-screen todo list view inspired by Things and Bear

import OSLog
import SwiftUI
import CoreData

// MARK: - Tag Badge Component

struct TagBadge: View {
    let tag: String
    var compact: Bool = false

    private var tagName: String {
        if TodoTagHelper.isStudentTag(tag) {
            return TodoTagHelper.leafTagName(tag)
        }
        return TodoTagHelper.tagName(tag)
    }

    private var tagColor: TagColor {
        TodoTagHelper.tagColor(tag)
    }

    var body: some View {
        Text(tagName)
            .font(.system(size: compact ? 11 : 13, weight: .medium))
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, compact ? 2 : 4)
            .background(tagColor.lightColor)
            .foregroundStyle(tagColor.color)
            .clipShape(RoundedRectangle(cornerRadius: compact ? 4 : 6))
    }
}

// MARK: - Tag Picker Component

struct TagPicker: View {
    private static let logger = Logger.todos
    @Binding var selectedTags: [String]
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(sortDescriptors: CDStudent.sortByName)private var studentsRaw: FetchedResults<CDStudent>
    private var students: [CDStudent] { Array(studentsRaw).uniqueByID.filter(\.isEnrolled) }
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDTodoItem.createdAt, ascending: false)]) private var allTodos: FetchedResults<CDTodoItem>
    @State private var isShowingCustomTagSheet = false
    @State private var searchText = ""
    @State private var pendingNewTagName = ""
    @State private var pendingTagColor: TagColor = .blue
    @State private var editingOriginalTag: String?
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Search/Filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))

                TextField("Search tags", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(AppTheme.ScaledFont.body)
                    .focused($isSearchFieldFocused)
                    .onSubmit {
                        createTagFromSearchIfNeeded()
                    }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            #if os(iOS)
            .background(Color(.systemGray6))
            #else
            .background(Color(nsColor: .controlBackgroundColor))
            #endif
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // CDStudent tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filteredStudentTags, id: \.self) { tag in
                        TagButton(
                            tag: tag,
                            isSelected: selectedTags.contains(tag),
                            onToggle: { toggleTag(tag) }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }

            // Previously used non-student tags
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(filteredUsedTags, id: \.self) { tag in
                        TagButton(
                            tag: tag,
                            isSelected: selectedTags.contains(tag),
                            onToggle: { toggleTag(tag) },
                            onEdit: { beginEditing(tag: tag) }
                        )
                    }
                }
                .padding(.horizontal, 2)
            }

            // Selected tags
            if !selectedTags.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Selected Tags")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    FlowLayout(spacing: 8) {
                        ForEach(selectedTags, id: \.self) { tag in
                            HStack(spacing: 4) {
                                TagBadge(tag: tag)

                                Button {
                                    selectedTags.removeAll { $0 == tag }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 14))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .contextMenu {
                                if !TodoTagHelper.isStudentTag(tag) {
                                    Button("Edit Tag") {
                                        beginEditing(tag: tag)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingCustomTagSheet, onDismiss: {
            pendingNewTagName = ""
            pendingTagColor = .blue
            editingOriginalTag = nil
        }, content: {
            CustomTagSheet(
                selectedTags: $selectedTags,
                initialName: pendingNewTagName,
                initialColor: pendingTagColor,
                isEditing: editingOriginalTag != nil,
                onSave: { savedTag in
                    handleSavedTag(savedTag)
                }
            )
        })
        #if os(macOS)
        .onExitCommand {
            searchText = ""
            isSearchFieldFocused = true
        }
        #endif
    }

    private var usedNonStudentTags: [String] {
        let tags = Set(
            allTodos
                .flatMap(\.tagsArray)
                .filter { !TodoTagHelper.isStudentTag($0) }
        )
        return tags.sorted {
            TodoTagHelper.tagName($0).localizedCaseInsensitiveCompare(TodoTagHelper.tagName($1)) == .orderedAscending
        }
    }

    private var filteredUsedTags: [String] {
        guard !searchText.isEmpty else { return usedNonStudentTags }
        return usedNonStudentTags.filter {
            TodoTagHelper.tagName($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var filteredStudentTags: [String] {
        let tags = students.map { TodoTagHelper.createStudentTag(name: $0.fullName) }
        guard !searchText.isEmpty else { return tags }
        return tags.filter {
            TodoTagHelper.leafTagName($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var hasSearchResults: Bool {
        guard !searchText.trimmed().isEmpty else { return true }
        return !filteredStudentTags.isEmpty || !filteredUsedTags.isEmpty
    }

    private func toggleTag(_ tag: String) {
        if let index = selectedTags.firstIndex(of: tag) {
            selectedTags.remove(at: index)
        } else {
            selectedTags.append(tag)
        }
    }

    private func createTagFromSearchIfNeeded() {
        let trimmed = searchText.trimmed()
        guard !trimmed.isEmpty else { return }
        guard hasSearchResults == false else { return }
        editingOriginalTag = nil
        pendingNewTagName = trimmed
        pendingTagColor = .blue
        isShowingCustomTagSheet = true
    }

    private func beginEditing(tag: String) {
        guard !TodoTagHelper.isStudentTag(tag) else { return }
        editingOriginalTag = tag
        pendingNewTagName = TodoTagHelper.tagName(tag)
        pendingTagColor = TodoTagHelper.tagColor(tag)
        isShowingCustomTagSheet = true
    }

    private func handleSavedTag(_ savedTag: String) {
        if let originalTag = editingOriginalTag {
            selectedTags = uniqueTags(selectedTags.map { $0 == originalTag ? savedTag : $0 })

            for todo in allTodos where todo.tagsArray.contains(originalTag) {
                let updated = todo.tagsArray.map { $0 == originalTag ? savedTag : $0 }
                todo.tagsArray = uniqueTags(updated)
            }

            do {
                try viewContext.save()
            } catch {
                Self.logger.error("[\(#function)] Failed to save tag edit: \(error)")
            }
        } else if !selectedTags.contains(savedTag) {
            selectedTags.append(savedTag)
        }
    }

    private func uniqueTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.filter { seen.insert($0).inserted }
    }
}

struct TagButton: View {
    let tag: String
    let isSelected: Bool
    let onToggle: () -> Void
    var onEdit: (() -> Void)?

    private var tagName: String {
        if TodoTagHelper.isStudentTag(tag) {
            return TodoTagHelper.leafTagName(tag)
        }
        return TodoTagHelper.tagName(tag)
    }

    private var tagColor: TagColor {
        TodoTagHelper.tagColor(tag)
    }

    var body: some View {
        Button {
            onToggle()
        } label: {
            HStack(spacing: 4) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                }
                Text(tagName)
            }
            .font(AppTheme.ScaledFont.captionSemibold)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isSelected ? tagColor.color : tagColor.lightColor)
            .foregroundStyle(isSelected ? .white : tagColor.color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onEdit {
                Button("Edit Tag") {
                    onEdit()
                }
            }
        }
    }
}

struct CustomTagSheet: View {
    @Binding var selectedTags: [String]
    @Environment(\.dismiss) private var dismiss

    @State private var tagName: String
    @State private var selectedColor: TagColor
    let isEditing: Bool
    let onSave: ((String) -> Void)?

    init(
        selectedTags: Binding<[String]>,
        initialName: String = "",
        initialColor: TagColor = .blue,
        isEditing: Bool = false,
        onSave: ((String) -> Void)? = nil
    ) {
        self._selectedTags = selectedTags
        self._tagName = State(initialValue: initialName)
        self._selectedColor = State(initialValue: initialColor)
        self.isEditing = isEditing
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tag Name") {
                    TextField("Enter tag name", text: $tagName)
                }

                Section("Color") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 60))], spacing: 12) {
                        ForEach(TagColor.allCases, id: \.self) { color in
                            Button {
                                selectedColor = color
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(color.color)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle()
                                                .strokeBorder(Color.primary, lineWidth: selectedColor == color ? 3 : 0)
                                        )

                                    Text(color.rawValue)
                                        .font(AppTheme.ScaledFont.captionSmall)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Tag" : "New Tag")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") {
                        let tag = TodoTagHelper.createTag(name: tagName, color: selectedColor)
                        if let onSave {
                            onSave(tag)
                        } else if !selectedTags.contains(tag) {
                            selectedTags.append(tag)
                        }
                        dismiss()
                    }
                    .disabled(tagName.isEmpty)
                }
            }
        }
    }
}
