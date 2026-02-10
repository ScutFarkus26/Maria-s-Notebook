import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @FocusState private var isTextEditorFocused: Bool

    let note: Note
    var onSaved: (() -> Void)? = nil

    @State private var bodyText: String
    @State private var category: NoteCategory
    @State private var includeInReport: Bool
    @State private var isPinned: Bool

    init(note: Note, onSaved: (() -> Void)? = nil) {
        self.note = note
        self.onSaved = onSaved
        _bodyText = State(initialValue: note.body)
        _category = State(initialValue: note.category)
        _includeInReport = State(initialValue: note.includeInReport)
        _isPinned = State(initialValue: note.isPinned)
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
        .onAppear {
            // Auto-focus text editor on macOS
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                isTextEditorFocused = true
            }
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
        .onAppear {
            // Auto-focus text editor on iOS
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                isTextEditorFocused = true
            }
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
                    // Category picker as elegant chips
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Category")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .tracking(0.5)
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(NoteCategory.allCases, id: \.self) { cat in
                                    CategoryChip(
                                        category: cat,
                                        isSelected: category == cat
                                    ) {
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            category = cat
                                        }
                                    }
                                }
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

                            Toggle(isOn: $includeInReport) {
                                HStack(spacing: 6) {
                                    Image(systemName: "flag.fill")
                                        .font(.system(size: 12))
                                    Text("Flag for Report")
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
    }

    private var canSave: Bool {
        !bodyText.trimmed().isEmpty
    }

    private func save() {
        let trimmed = bodyText.trimmed()
        guard !trimmed.isEmpty else { return }
        note.body = trimmed
        note.category = category
        note.includeInReport = includeInReport
        note.isPinned = isPinned
        note.updatedAt = Date()
        try? modelContext.save()
        onSaved?()
        dismiss()
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    let category: NoteCategory
    let isSelected: Bool
    let action: () -> Void
    
    private var categoryColor: Color {
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
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(categoryColor)
                    .frame(width: 8, height: 8)
                Text(category.rawValue.capitalized)
                    .font(.system(size: 14, weight: isSelected ? .semibold : .regular, design: .rounded))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(isSelected ? categoryColor.opacity(0.15) : Color.secondary.opacity(0.1))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(isSelected ? categoryColor.opacity(0.4) : Color.clear, lineWidth: 1.5)
            }
            .foregroundStyle(isSelected ? categoryColor : .primary)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    struct Wrapper: View {
        @Environment(\.modelContext) private var modelContext
        @State private var note: Note
        init() {
            _note = State(initialValue: Note(body: "Sample note body", scope: .all, category: .general, includeInReport: false))
        }
        var body: some View {
            NoteEditSheet(note: note)
        }
    }
    return Wrapper()
        .previewEnvironment()
}
