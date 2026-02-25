import SwiftUI
import SwiftData
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NoteEditSheet: View {
    private static let logger = Logger.notes

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isTextEditorFocused: Bool

    let note: Note
    var onSaved: (() -> Void)? = nil

    @State private var bodyText: String
    @State private var tags: [String]
    @State private var includeInReport: Bool
    @State private var isPinned: Bool
    @State private var needsFollowUp: Bool
    @State private var showingTagPicker: Bool = false

    init(note: Note, onSaved: (() -> Void)? = nil) {
        self.note = note
        self.onSaved = onSaved
        _bodyText = State(initialValue: note.body)
        _tags = State(initialValue: note.tags)
        _includeInReport = State(initialValue: note.includeInReport)
        _isPinned = State(initialValue: note.isPinned)
        _needsFollowUp = State(initialValue: note.needsFollowUp)
    }

    var body: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Note")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 12) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!canSave)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Content
            formContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 500)
        .presentationSizingFitted()
        .task {
            // Auto-focus text editor on macOS
            do {
                try await Task.sleep(for: .milliseconds(200))
            } catch {
                Self.logger.warning("Failed to sleep for auto-focus: \(error)")
            }
            isTextEditorFocused = true
        }
        #else
        NavigationStack {
            formContent
                .navigationTitle("Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            // Auto-focus text editor on iOS
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                Self.logger.warning("Failed to sleep for auto-focus: \(error)")
            }
            isTextEditorFocused = true
        }
        #endif
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Main text editor - the star of the show
                TextEditor(text: $bodyText)
                    .focused($isTextEditorFocused)
                    .font(.system(size: 18, design: .default))
                    .lineSpacing(6)
                    .frame(minHeight: 300)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 24)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                
                Divider()
                    .padding(.horizontal, 28)
                
                // Metadata section - subtle and compact
                VStack(alignment: .leading, spacing: 20) {
                    // Tags section
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tags")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(tags, id: \.self) { tag in
                                    HStack(spacing: 4) {
                                        TagBadge(tag: tag)
                                        Button {
                                            withAnimation { tags.removeAll { $0 == tag } }
                                        } label: {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                Button {
                                    showingTagPicker = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "plus")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Add Tag")
                                            .font(.system(size: 14, weight: .medium, design: .rounded))
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.secondary.opacity(0.1))
                                    .clipShape(RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                    
                    // Toggles and image indicator
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 20) {
                            Toggle(isOn: $isPinned) {
                                HStack(spacing: 6) {
                                    Image(systemName: "pin.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.orange)
                                    Text("Pin to Top")
                                        .font(.system(size: 15, design: .rounded))
                                }
                            }
                            .toggleStyle(.switch)

                            Toggle(isOn: $needsFollowUp) {
                                HStack(spacing: 6) {
                                    Image(systemName: "flag.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                    Text("Follow Up")
                                        .font(.system(size: 15, design: .rounded))
                                }
                            }
                            .toggleStyle(.switch)

                            Toggle(isOn: $includeInReport) {
                                HStack(spacing: 6) {
                                    Image(systemName: "doc.text.fill")
                                        .font(.system(size: 12))
                                    Text("Include in Report")
                                        .font(.system(size: 15, design: .rounded))
                                }
                            }
                            .toggleStyle(.switch)

                            Spacer()
                        }

                        if let path = note.imagePath, !path.isEmpty {
                            HStack(spacing: 6) {
                                Image(systemName: "photo.fill")
                                    .font(.system(size: 12))
                                Text("Photo attached")
                                    .font(.system(size: 15, design: .rounded))
                            }
                            .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
                #if os(macOS)
                .background(Color(NSColor.textBackgroundColor))
                #else
                .background(Color(uiColor: .systemBackground))
                #endif
            }
        }
        #if os(macOS)
        .background(Color(NSColor.textBackgroundColor))
        #else
        .background(Color(uiColor: .systemBackground))
        #endif
        .dismissKeyboardOnScroll()
        .sheet(isPresented: $showingTagPicker) {
            NoteTagPickerSheet(selectedTags: $tags)
        }
    }

    private var canSave: Bool {
        !bodyText.trimmed().isEmpty
    }

    private func save() {
        let trimmed = bodyText.trimmed()
        guard !trimmed.isEmpty else { return }
        note.body = trimmed
        note.tags = tags
        note.includeInReport = includeInReport
        note.isPinned = isPinned
        note.needsFollowUp = needsFollowUp
        note.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save note: \(error)")
        }
        onSaved?()
        dismiss()
    }
}

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
                                        .font(.system(size: 11))
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

#Preview {
    struct Wrapper: View {
        @Environment(\.modelContext) private var modelContext
        @State private var note: Note
        init() {
            _note = State(initialValue: Note(body: "Sample note body", scope: .all, tags: [], includeInReport: false))
        }
        var body: some View {
            NoteEditSheet(note: note)
        }
    }
    return Wrapper()
        .previewEnvironment()
}
