import SwiftUI
import SwiftData

// MARK: - Note Tag Picker Sheet

struct NoteTagPickerSheet: View {
    @Binding var selectedTags: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var showingCustomTagSheet: Bool = false
    @State private var pendingNewTagName: String = ""
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
        return tagSet.sorted { TagHelper.tagName($0).localizedCaseInsensitiveCompare(TagHelper.tagName($1)) == .orderedAscending }
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
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
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

                        if !hasSearchResults {
                            Button {
                                createTagFromSearch()
                            } label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(.blue)
                                    Text("Create \"\(searchText.trimmingCharacters(in: .whitespacesAndNewlines))\"")
                                }
                            }
                        }
                    }

                    Section {
                        Button {
                            pendingNewTagName = ""
                            showingCustomTagSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.blue)
                                Text("Create New Tag")
                            }
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
            .sheet(isPresented: $showingCustomTagSheet) {
                NoteCustomTagSheet(initialName: pendingNewTagName) { newTag in
                    if !selectedTags.contains(newTag) {
                        selectedTags.append(newTag)
                    }
                    searchText = ""
                    isSearchFocused = true
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

    private func createTagFromSearch() {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        pendingNewTagName = trimmed
        showingCustomTagSheet = true
    }

    private func createTagFromSearchIfNeeded() {
        guard !hasSearchResults else { return }
        createTagFromSearch()
    }
}

// MARK: - Custom Tag Creation Sheet

struct NoteCustomTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tagName: String
    @State private var selectedColor: TagColor = .blue
    let onSave: (String) -> Void

    init(initialName: String = "", onSave: @escaping (String) -> Void) {
        _tagName = State(initialValue: initialName)
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
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Preview") {
                    if !tagName.trimmed().isEmpty {
                        TagBadge(tag: TagHelper.createTag(name: tagName.trimmed(), color: selectedColor))
                    }
                }
            }
            .navigationTitle("New Tag")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let trimmed = tagName.trimmed()
                        guard !trimmed.isEmpty else { return }
                        onSave(TagHelper.createTag(name: trimmed, color: selectedColor))
                        dismiss()
                    }
                    .disabled(tagName.trimmed().isEmpty)
                }
            }
        }
    }
}
