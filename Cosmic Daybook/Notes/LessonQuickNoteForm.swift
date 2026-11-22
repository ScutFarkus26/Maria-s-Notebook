//
//  LessonQuickNoteForm.swift
//  Cosmic Daybook
//
//  The quick note's one field: the lesson and its children above, a line to
//  type, Save. The same view is the Mac's Quick Note window and the iPad's
//  sheet (`LessonQuickNote`); what it saves on is the caller's.
//

import CoreData
import SwiftUI

/// The lesson a quick note is about, read once for the header.
struct LessonQuickNoteSubject: Equatable {
    let presentationID: UUID
    let lessonName: String
    /// The children in short form ("Maya S, Theo L"), or empty.
    let childrenLine: String
    /// "Given today" / "Not marked given yet".
    let status: String

    init(presentationID: UUID, lessonName: String, childrenLine: String, status: String) {
        self.presentationID = presentationID
        self.lessonName = lessonName
        self.childrenLine = childrenLine
        self.status = status
    }

    /// The header for `presentation`, with its children's short names.
    init?(_ presentation: CDLessonAssignment, context: NSManagedObjectContext) {
        guard let id = presentation.id else { return nil }
        let name = presentation.lesson?.name.trimmed() ?? ""
        let studentIDs = presentation.resolvedStudentIDs
        var names: [String] = []
        if !studentIDs.isEmpty {
            let request = CDFetchRequest(CDStudent.self)
            request.predicate = NSPredicate(format: "id IN %@", studentIDs)
            names = context.safeFetch(request).map(\.shortName)
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        self.init(
            presentationID: id,
            lessonName: name.isEmpty ? "Untitled Lesson" : name,
            childrenLine: PresentationSessionSummary.list(names),
            status: LessonQuickNote.statusLine(for: presentation)
        )
    }
}

struct LessonQuickNoteForm: View {
    let subject: LessonQuickNoteSubject
    /// Saves the text; false shows "Couldn't save" and keeps what was typed.
    let onSave: (String) -> Bool
    let onCancel: () -> Void

    @State private var text = ""
    @State private var saveFailed = false
    @FocusState private var isFieldFocused: Bool

    private var canSave: Bool { !text.trimmed().isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            TextField("What happened?", text: $text, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...8)
                .focused($isFieldFocused)
                .onSubmit(save)
                .accessibilityLabel("Quick note about \(subject.lessonName)")
            if saveFailed {
                Text("Couldn't save the note. Try again.")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.red)
            }
            Text("Marked “to fill in”, so the end-of-day chat asks you for the rest.")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canSave)
                    .help("Save (⌘↩)")
            }
        }
        .padding(16)
        .defaultFocus($isFieldFocused, true)
        // `defaultFocus` is read when the window first appears; a window
        // opened again, or a sheet, is focused here as well.
        .onAppear { isFieldFocused = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(subject.lessonName)
                .font(AppTheme.ScaledFont.calloutSemibold)
            if !subject.childrenLine.isEmpty {
                Text(subject.childrenLine)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
            Text(subject.status)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private func save() {
        guard canSave else { return }
        if onSave(text) {
            text = ""
            saveFailed = false
        } else {
            saveFailed = true
        }
    }
}

/// The quick note on the iPad and iPhone: the form in a sheet over Today.
struct LessonQuickNoteSheet: View {
    let presentationID: UUID
    let onDone: () -> Void

    @Environment(\.managedObjectContext) private var viewContext

    var body: some View {
        Group {
            if let presentation = viewContext.object(CDLessonAssignment.self, id: presentationID),
               let subject = LessonQuickNoteSubject(presentation, context: viewContext) {
                LessonQuickNoteForm(
                    subject: subject,
                    onSave: { text in
                        let saved = LessonQuickNote.save(
                            text: text, presentationID: presentationID, context: viewContext
                        )
                        if saved { onDone() }
                        return saved
                    },
                    onCancel: onDone
                )
            } else {
                ContentUnavailableView(
                    "This Lesson Is Gone",
                    systemImage: "book.closed",
                    description: Text("It may have been removed on another device.")
                )
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
