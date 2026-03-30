import SwiftUI
import SwiftData

/// Tag picker for resources — excludes student-specific tags.
/// Shown as a NavigationLink destination inside import/edit sheets.
struct ResourceTagPicker: View {
    @Binding var selectedTags: [String]

    @Query(sort: \Resource.title) private var allResources: [Resource]
    @Query(sort: \TodoItem.createdAt, order: .reverse) private var allTodos: [TodoItem]

    @State private var searchText = ""
    @State private var isShowingNewTag = false
    @State private var pendingTagName = ""
    @State private var pendingTagColor: TagColor = .blue

    /// All unique non-student tags from resources and todos.
    private var availableTags: [String] {
        var tagSet = Set<String>()

        for resource in allResources {
            for tag in resource.tags where !TodoTagHelper.isStudentTag(tag) {
                tagSet.insert(tag)
            }
        }

        for todo in allTodos {
            for tag in todo.tags where !TodoTagHelper.isStudentTag(tag) {
                tagSet.insert(tag)
            }
        }

        return tagSet.sorted {
            TodoTagHelper.tagName($0)
                .localizedCaseInsensitiveCompare(TodoTagHelper.tagName($1)) == .orderedAscending
        }
    }

    private var filteredTags: [String] {
        guard !searchText.isEmpty else { return availableTags }
        let query = searchText.lowercased()
        return availableTags.filter {
            TodoTagHelper.tagName($0).lowercased().contains(query)
        }
    }

    var body: some View {
        List {
            // Selected tags
            if !selectedTags.isEmpty {
                Section("Selected") {
                    ForEach(selectedTags, id: \.self) { tag in
                        Button {
                            selectedTags.removeAll { $0 == tag }
                        } label: {
                            HStack {
                                TagBadge(tag: tag)
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }

            // Available tags
            Section(selectedTags.isEmpty ? "Tags" : "Available") {
                let unselected = filteredTags.filter { !selectedTags.contains($0) }
                if unselected.isEmpty {
                    if searchText.isEmpty {
                        Text("No tags yet — create one below")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No matching tags")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(unselected, id: \.self) { tag in
                        Button {
                            selectedTags.append(tag)
                        } label: {
                            HStack {
                                TagBadge(tag: tag)
                                Spacer()
                            }
                        }
                    }
                }
            }

            // Create new tag
            Section {
                Button {
                    pendingTagName = searchText.trimmed()
                    pendingTagColor = .blue
                    isShowingNewTag = true
                } label: {
                    Label("Create New Tag", systemImage: "plus.circle")
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search tags")
        .navigationTitle("Tags")
        .inlineNavigationTitle()
        .sheet(isPresented: $isShowingNewTag) {
            pendingTagName = ""
        } content: {
            CustomTagSheet(
                selectedTags: $selectedTags,
                initialName: pendingTagName,
                initialColor: pendingTagColor,
                onSave: { savedTag in
                    if !selectedTags.contains(savedTag) {
                        selectedTags.append(savedTag)
                    }
                }
            )
        }
    }
}
