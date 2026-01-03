import SwiftUI
import SwiftData

struct NoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let note: Note
    var onSaved: (() -> Void)? = nil

    @State private var bodyText: String
    @State private var category: NoteCategory
    @State private var includeInReport: Bool

    init(note: Note, onSaved: (() -> Void)? = nil) {
        self.note = note
        self.onSaved = onSaved
        _bodyText = State(initialValue: note.body)
        _category = State(initialValue: note.category)
        _includeInReport = State(initialValue: note.includeInReport)
    }

    var body: some View {
        #if os(macOS)
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Note")
                .font(.system(size: 20, weight: .bold, design: .rounded))

            formContent

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 380)
        .presentationSizingFitted()
        #else
        NavigationStack {
            formContent
                .navigationTitle("Edit Note")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }.disabled(!canSave)
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #endif
    }

    private var formContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Category
                VStack(alignment: .leading, spacing: 8) {
                    Text("Category")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    Picker("Category", selection: $category) {
                        ForEach(NoteCategory.allCases, id: \.self) { cat in
                            Text(cat.rawValue.capitalized).tag(cat)
                        }
                    }
                    .pickerStyle(.menu)
                }

                // Body
                VStack(alignment: .leading, spacing: 8) {
                    Text("Note")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                    TextEditor(text: $bodyText)
                        .font(.system(size: 17, design: .rounded))
                        .frame(minHeight: 160)
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.primary.opacity(0.05))
                        )
                }

                // Include in report
                Toggle("Flag for Report", isOn: $includeInReport)
                    .font(.system(size: 17, design: .rounded))

                if let path = note.imagePath, !path.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                        Text("This note has an attached photo")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(16)
        }
    }

    private var canSave: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        let trimmed = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        note.body = trimmed
        note.category = category
        note.includeInReport = includeInReport
        note.updatedAt = Date()
        do {
            try modelContext.save()
        } catch {
            // If save fails, still dismiss to avoid trapping the user; log error for debugging
            print("Error saving note: \(error)")
        }
        onSaved?()
        dismiss()
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
