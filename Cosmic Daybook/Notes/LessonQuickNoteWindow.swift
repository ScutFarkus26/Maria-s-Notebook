//
//  LessonQuickNoteWindow.swift
//  Cosmic Daybook
//
//  The Mac's Quick Note: one small floating window with one field, opened by
//  Today's "Given — Quick Note" and by File › Quick Note on the Lesson (⌃⌘J).
//
//  A plain `Window` scene, as the plan's Apple guidance says: not a
//  `UtilityWindow` (it hides while the app is inactive, and isn't said to
//  focus a field on open), not a panel (no typing controls in panels) and not
//  a sheet (modal on the Mac). The lesson comes from `LessonQuickNoteTarget`;
//  each open starts a fresh note, focused.
//

#if os(macOS)
import CoreData
import SwiftUI

struct LessonQuickNoteWindowScene: Scene {
    let dependencies: DetailWindowDependencies

    var body: some Scene {
        Window("Quick Note", id: LessonQuickNote.windowID) {
            DetailWindowGate(
                dependencies: dependencies,
                minimumSize: CGSize(width: 380, height: 180),
                loadingStyle: .labeled,
                countsAsEditor: true
            ) {
                LessonQuickNoteWindowHost()
            }
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 440, height: 240)
        .windowLevel(.floating)
        // A `cosmicdaybook://` link goes to the main window, never here.
        .handlesExternalEvents(matching: [])
    }
}

/// The window's content: the form for the target lesson, or why there is none.
private struct LessonQuickNoteWindowHost: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismissWindow) private var dismissWindow

    private var target: LessonQuickNoteTarget { .shared }

    var body: some View {
        content
            .frame(width: 440)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var content: some View {
        if let id = target.presentationID,
           let presentation = viewContext.object(CDLessonAssignment.self, id: id),
           !presentation.isDeleted,
           let subject = LessonQuickNoteSubject(presentation, context: viewContext) {
            LessonQuickNoteForm(
                subject: subject,
                onSave: { text in
                    let saved = LessonQuickNote.save(text: text, presentationID: id, context: viewContext)
                    if saved { dismissWindow(id: LessonQuickNote.windowID) }
                    return saved
                },
                onCancel: { dismissWindow(id: LessonQuickNote.windowID) }
            )
            // A fresh note, and the field focused again, on every open.
            .id(target.openCount)
        } else {
            ContentUnavailableView(
                "No Lesson Today",
                systemImage: "book.closed",
                description: Text("Mark a lesson given on Today, then type a quick note here.")
            )
            .padding()
        }
    }
}

/// File › Quick Note on the Lesson (⌃⌘J): the window, on the lesson just
/// given or the one in progress (`LessonQuickNote.target`).
struct LessonQuickNoteCommands: Commands {
    let notebookOpener: NotebookOpener

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Quick Note on the Lesson") { open() }
                .keyboardShortcut("j", modifiers: [.command, .control])
                .disabled(notebookOpener.notebook == nil)
        }
    }

    private func open() {
        guard let notebook = notebookOpener.notebook else { return }
        let target = LessonQuickNoteTarget.shared
        target.open(LessonQuickNote.target(
            lastGivenID: target.lastGivenID,
            context: notebook.classroomWorkspace.activeStack.viewContext
        ))
        openWindow(id: LessonQuickNote.windowID)
    }
}
#endif
