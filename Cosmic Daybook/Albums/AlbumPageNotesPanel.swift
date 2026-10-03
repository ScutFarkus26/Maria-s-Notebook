// AlbumPageNotesPanel.swift
// Per-page notes panel

import CoreData
import SwiftUI

struct AlbumPageNotesPanel: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dependencies) private var dependencies
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumPageNote.createdAt, ascending: true)
    ])
    private var allNotes: FetchedResults<CDAlbumPageNote>
    let album: Album
    let pageIndex: Int
    let lessonTitle: String

    @State private var draft = ""

    private var pageNotes: [CDAlbumPageNote] {
        allNotes.filter { $0.albumID == album.id && Int($0.pageIndex) == pageIndex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(lessonTitle) — p. \(pageIndex + 1)", systemImage: "note.text")
                .font(.headline)
                .lineLimit(1)
            if !pageNotes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(pageNotes) { note in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.text)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                HStack {
                                    Text(note.createdAt ?? Date(), style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(role: .destructive) {
                                        context.delete(note)
                                        dependencies.saveCoordinator.save(context, reason: "Delete page note")
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(album.subject.color.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            TextField("Add a note for this page…", text: $draft, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveDraft)
            HStack {
                Spacer()
                Button("Save Note", action: saveDraft)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func saveDraft() {
        AlbumUserDataStore.addNote(albumID: album.id, pageIndex: pageIndex,
                         lessonTitle: lessonTitle, text: draft, in: context)
        draft = ""
    }
}
