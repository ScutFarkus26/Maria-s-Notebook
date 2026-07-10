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
    @FocusState var isTextEditorFocused: Bool

    let note: CDNote
    var onSaved: (() -> Void)?

    @State var bodyText: String
    @State var tags: [String]
    @State var includeInReport: Bool
    @State var isPinned: Bool
    @State var needsFollowUp: Bool
    @State var showingTagPicker: Bool = false

    init(note: CDNote, onSaved: (() -> Void)? = nil) {
        self.note = note
        self.onSaved = onSaved
        _bodyText = State(initialValue: note.body)
        _tags = State(initialValue: (note.tags as? [String]) ?? [])
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
                .inlineNavigationTitle()
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
        note.tags = tags as NSObject
        note.includeInReport = includeInReport
        note.isPinned = isPinned
        note.needsFollowUp = needsFollowUp
        note.updatedAt = Date()
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save note: \(error)")
        }
        onSaved?()
        dismiss()
    }
}

#Preview {
    let stack = CoreDataStack.preview
    let ctx = stack.viewContext
    let note = CDNote(context: ctx)
    note.body = "Sample note body"
    note.scope = .all
    note.includeInReport = false

    return NoteEditSheet(note: note)
        .previewEnvironment(using: stack)
}
