import SwiftUI
import CoreData
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct NoteEditSheet: View {
    private static let logger = Logger.notes

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @FocusState var isTextEditorFocused: Bool

    let note: CDNote
    var onSaved: (() -> Void)?

    @State var bodyText: String
    @State var tags: [String]
    @State var includeInReport: Bool
    @State var isPinned: Bool
    @State var needsFollowUp: Bool
    @State var showingTagPicker: Bool = false
    /// Shown when Save fails; the sheet stays open with her changes.
    @State private var saveErrorMessage: String?
    @State private var isConfirmingDiscard = false

    /// The note as the sheet opened it, to tell whether closing loses anything.
    private let opened: Snapshot

    private struct Snapshot: Equatable {
        var body: String
        var tags: [String]
        var includeInReport: Bool
        var isPinned: Bool
        var needsFollowUp: Bool
    }

    init(note: CDNote, onSaved: (() -> Void)? = nil) {
        self.note = note
        self.onSaved = onSaved
        let opened = Snapshot(
            body: note.body,
            tags: (note.tags as? [String]) ?? [],
            includeInReport: note.includeInReport,
            isPinned: note.isPinned,
            needsFollowUp: note.needsFollowUp
        )
        self.opened = opened
        bodyText = opened.body
        tags = opened.tags
        includeInReport = opened.includeInReport
        isPinned = opened.isPinned
        needsFollowUp = opened.needsFollowUp
    }

    var body: some View {
        content
            // A swipe down or a tap outside used to throw her edits away.
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog(
                "Discard your changes?",
                isPresented: $isConfirmingDiscard,
                titleVisibility: .visible
            ) {
                Button("Discard Changes", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            } message: {
                Text("What you changed in this note hasn't been saved.")
            }
            .alert("Couldn't Save the Note", isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { if !$0 { saveErrorMessage = nil } }
            )) {
                Button("OK") { saveErrorMessage = nil }
            } message: {
                Text(saveErrorMessage ?? NoteEditorSave.notSavedMessage)
            }
    }

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Note")
                    .font(AppTheme.ScaledFont.header)
                    .foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 12) {
                    Button("Cancel") { cancel() }
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
            .background(Color.controlBackgroundColor())
            
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
                .inlineNavigationTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { cancel() }
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

    private var hasUnsavedChanges: Bool {
        Snapshot(
            body: bodyText, tags: tags, includeInReport: includeInReport,
            isPinned: isPinned, needsFollowUp: needsFollowUp
        ) != opened
    }

    private func cancel() {
        if hasUnsavedChanges {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    /// Closes only once the edit is saved; a failed save used to close the
    /// sheet as if it had worked. A failed save leaves the note as it was, so
    /// Discard Changes discards and no later save carries the edit.
    private func save() {
        let trimmed = bodyText.trimmed()
        guard !trimmed.isEmpty else { return }
        let edit = NoteEditorSave.SheetEdit(
            body: trimmed, tags: tags, includeInReport: includeInReport,
            isPinned: isPinned, needsFollowUp: needsFollowUp
        )
        switch NoteEditorSave.save(edit, to: note, in: viewContext, saveCoordinator: dependencies.saveCoordinator) {
        case .saved:
            onSaved?()
            dismiss()
        case .failed(let message):
            saveErrorMessage = message
        }
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct NoteEditSheetPreview: View {
    var body: some View {
        let stack = CoreDataStack.preview
        let ctx = stack.viewContext
        let note = CDNote(context: ctx)
        note.body = "Sample note body"
        note.scope = .all
        note.includeInReport = false

        return NoteEditSheet(note: note)
            .previewEnvironment(using: stack)
    }
}

#Preview {
    NoteEditSheetPreview()
}
