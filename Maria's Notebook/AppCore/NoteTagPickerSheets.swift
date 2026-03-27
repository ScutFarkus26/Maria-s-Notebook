import SwiftUI
import SwiftData

// MARK: - Note Tag Picker Sheet

struct NoteTagPickerSheet: View {
    @Binding var selectedTags: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var newTagColor: TagColor = .blue
    @FocusState private var isSearchFocused: Bool

    /// All tags currently used across notes in the database
    @Query private var allNotes: [Note]

    private var allUsedTags: [String] {
        var tagSet = Set<String>()
        for note in allNotes {
            for tag in note.tags {
                tagSet.insert(tag)
            }
        }
        return tagSet.sorted {
            TagHelper.tagName($0)
                .localizedCaseInsensitiveCompare(TagHelper.tagName($1)) == .orderedAscending
        }
    }

    private var filteredTags: [String] {
        if searchText.isEmpty { return allUsedTags }
        return allUsedTags.filter {
            TagHelper.tagName($0).localizedCaseInsensitiveContains(searchText)
        }
    }

    private var availableTags: [String] {
        filteredTags.filter { !selectedTags.contains($0) }
    }

    /// Whether the search text matches any existing tags
    private var hasSearchResults: Bool {
        let trimmed = searchText.trimmed()
        guard !trimmed.isEmpty else { return true }
        return !filteredTags.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field — outside the List so keyboard events work reliably
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14))

                    TextField("Search or create tags", text: $searchText)
                        .textFieldStyle(.plain)
                        .focused($isSearchFocused)
                        .onSubmit {
                            createTagFromSearchIfNeeded()
                        }

                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            isSearchFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.system(size: 14))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                #if os(macOS)
                .background(Color(nsColor: .controlBackgroundColor))
                #else
                .background(Color(.systemGray6))
                #endif

                Divider()

                List {
                    if !selectedTags.isEmpty {
                        Section("Selected") {
                            ForEach(selectedTags, id: \.self) { tag in
                                HStack {
                                    TagBadge(tag: tag)
                                    Spacer()
                                    Button {
                                        selectedTags.removeAll { $0 == tag }
                                    } label: {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(TagHelper.tagColor(tag).color)
                                    }
                                }
                            }
                        }
                    }

                    if !availableTags.isEmpty {
                        Section("Available Tags") {
                            ForEach(availableTags, id: \.self) { tag in
                                Button {
                                    selectedTags.append(tag)
                                } label: {
                                    HStack {
                                        TagBadge(tag: tag)
                                        Spacer()
                                        Image(systemName: "circle")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }

                    if !hasSearchResults {
                        Section {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    TagBadge(
                                        tag: TagHelper.createTag(
                                            name: searchText.trimmed(),
                                            color: newTagColor
                                        )
                                    )
                                    Spacer()
                                    Button {
                                        createTagImmediately()
                                    } label: {
                                        Image(systemName: "plus.circle.fill")
                                            .font(.title3)
                                            .foregroundStyle(newTagColor.color)
                                    }
                                    .buttonStyle(.plain)
                                }

                                HStack(spacing: 8) {
                                    ForEach(TagColor.allCases, id: \.self) { color in
                                        Button {
                                            newTagColor = color
                                        } label: {
                                            Circle()
                                                .fill(color.color)
                                                .frame(width: 24, height: 24)
                                                .overlay(
                                                    Circle()
                                                        .strokeBorder(
                                                            Color.primary,
                                                            lineWidth: newTagColor == color ? 2 : 0
                                                        )
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        } header: {
                            Text("Create \"\(searchText.trimmed())\"")
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if os(macOS)
            .onExitCommand {
                if !searchText.isEmpty {
                    searchText = ""
                    isSearchFocused = true
                } else {
                    dismiss()
                }
            }
            #endif
            .onAppear {
                isSearchFocused = true
            }
        }
    }

    private func createTagImmediately() {
        let trimmed = searchText.trimmed()
        guard !trimmed.isEmpty else { return }
        let newTag = TagHelper.createTag(name: trimmed, color: newTagColor)
        if !selectedTags.contains(newTag) {
            selectedTags.append(newTag)
        }
        searchText = ""
        newTagColor = .blue
        isSearchFocused = true
    }

    private func createTagFromSearchIfNeeded() {
        guard !hasSearchResults else { return }
        createTagImmediately()
    }
}
