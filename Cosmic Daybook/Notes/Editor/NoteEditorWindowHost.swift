import CoreData
import SwiftUI

#if os(macOS)
struct NoteEditorWindowHost: View {
    @FetchRequest private var notes: FetchedResults<CDNote>

    init(noteID: UUID) {
        _notes = FetchRequest(
            sortDescriptors: [],
            predicate: NSPredicate(format: "id == %@", noteID as CVarArg),
            animation: .default
        )
    }

    var body: some View {
        if let note = notes.first {
            NoteEditSheet(note: note)
                .navigationTitle(windowTitle(for: note))
                .frame(minWidth: 640, minHeight: 540)
        } else {
            ContentUnavailableView(
                "Observation Not Found",
                systemImage: "note.text",
                description: Text("This observation may have been deleted in another window.")
            )
            .frame(minWidth: 480, minHeight: 320)
        }
    }

    private func windowTitle(for note: CDNote) -> String {
        let firstLine = note.body
            .split(whereSeparator: \Character.isNewline)
            .first
            .map(String.init)?
            .trimmed()
        guard let firstLine, !firstLine.isEmpty else { return "Observation" }
        return String(firstLine.prefix(60))
    }
}
#endif
