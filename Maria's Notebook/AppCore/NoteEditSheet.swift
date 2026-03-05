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
    @FocusState var isTextEditorFocused: Bool

    let note: Note
    var onSaved: (() -> Void)? = nil

    @State var bodyText: String
    @State var tags: [String]
    @State var includeInReport: Bool
    @State var isPinned: Bool
    @State var needsFollowUp: Bool
    @State var showingTagPicker: Bool = false

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
                    .font(AppTheme.ScaledFont.header)
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
