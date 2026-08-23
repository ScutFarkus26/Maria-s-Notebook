// The three collection screens — Bookmarks, Notes, and Highlights — each
// grouped by album with jump-to-page rows, context menus, and swipe
// actions, plus the note editor sheet. All content comes from fetch
// requests, so edits made anywhere (including other devices) appear live.

import CoreData
import SwiftUI

struct AlbumBookmarksView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumBookmark.albumID, ascending: true),
        NSSortDescriptor(keyPath: \CDAlbumBookmark.pageIndex, ascending: true)
    ])
    private var bookmarks: FetchedResults<CDAlbumBookmark>

    private var grouped: [(album: Album, bookmarks: [CDAlbumBookmark])] {
        library.albums.compactMap { album in
            let items = bookmarks.filter { $0.albumID == album.id }
            return items.isEmpty ? nil : (album, items)
        }
    }

    var body: some View {
        Group {
            if grouped.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks Yet", systemImage: "bookmark")
                } description: {
                    Text("While reading an album, press ⌘D or tap the bookmark button to save your place.")
                }
            } else {
                List {
                    ForEach(grouped, id: \.album.id) { group in
                        Section {
                            ForEach(group.bookmarks) { bookmark in
                                row(bookmark, album: group.album)
                            }
                        } header: {
                            Label(group.album.title, systemImage: group.album.subject.symbol)
                                .foregroundStyle(group.album.subject.color)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
    }

    private func row(_ bookmark: CDAlbumBookmark, album: Album) -> some View {
        Button {
            nav.jump(albumID: bookmark.albumID, pageIndex: Int(bookmark.pageIndex))
        } label: {
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(album.subject.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bookmark.lessonTitle)
                        .font(.body.weight(.medium))
                    Text("p. \(Int(bookmark.pageIndex) + 1) · added "
                        + (bookmark.createdAt ?? Date()).formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove Bookmark", role: .destructive) {
                context.delete(bookmark)
                context.safeSave()
            }
        }
        .swipeActions {
            Button("Remove", systemImage: "bookmark.slash", role: .destructive) {
                context.delete(bookmark)
                context.safeSave()
            }
        }
    }
}

struct AlbumNotesView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumPageNote.albumID, ascending: true),
        NSSortDescriptor(keyPath: \CDAlbumPageNote.pageIndex, ascending: true),
        NSSortDescriptor(keyPath: \CDAlbumPageNote.createdAt, ascending: true)
    ])
    private var notes: FetchedResults<CDAlbumPageNote>
    @State private var editingNote: CDAlbumPageNote?

    private var grouped: [(album: Album, notes: [CDAlbumPageNote])] {
        library.albums.compactMap { album in
            let items = notes.filter { $0.albumID == album.id }
            return items.isEmpty ? nil : (album, items)
        }
    }

    var body: some View {
        Group {
            if grouped.isEmpty {
                ContentUnavailableView {
                    Label("No Notes Yet", systemImage: "note.text")
                } description: {
                    Text("While reading, use the note button in the toolbar to attach thoughts "
                         + "to any page. They stay searchable forever.")
                }
            } else {
                List {
                    ForEach(grouped, id: \.album.id) { group in
                        Section {
                            ForEach(group.notes) { note in
                                row(note, album: group.album)
                            }
                        } header: {
                            Label(group.album.title, systemImage: group.album.subject.symbol)
                                .foregroundStyle(group.album.subject.color)
                        }
                    }
                }
            }
        }
        .navigationTitle("Notes")
        .sheet(item: $editingNote) { note in
            AlbumNoteEditorSheet(note: note)
        }
    }

    private func row(_ note: CDAlbumPageNote, album: Album) -> some View {
        Button {
            nav.jump(albumID: note.albumID, pageIndex: Int(note.pageIndex))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(note.lessonTitle)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("p. \(Int(note.pageIndex) + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(note.text)
                    .font(.callout)
                    .lineLimit(4)
                Text((note.modifiedAt ?? Date()).formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit Note") { editingNote = note }
            Button("Delete Note", role: .destructive) { context.delete(note); context.safeSave() }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                context.delete(note)
                context.safeSave()
            }
        }
    }
}

struct AlbumHighlightsView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumHighlight.albumID, ascending: true),
        NSSortDescriptor(keyPath: \CDAlbumHighlight.pageIndex, ascending: true),
        NSSortDescriptor(keyPath: \CDAlbumHighlight.createdAt, ascending: true)
    ])
    private var highlights: FetchedResults<CDAlbumHighlight>

    private var grouped: [(album: Album, highlights: [CDAlbumHighlight])] {
        library.albums.compactMap { album in
            let items = highlights.filter { $0.albumID == album.id }
            return items.isEmpty ? nil : (album, items)
        }
    }

    var body: some View {
        Group {
            if grouped.isEmpty {
                ContentUnavailableView {
                    Label("No Highlights Yet", systemImage: "highlighter")
                } description: {
                    Text("Select text in any album and press ⇧⌘H — or use the highlighter "
                         + "button — to mark passages worth returning to.")
                }
            } else {
                List {
                    ForEach(grouped, id: \.album.id) { group in
                        Section {
                            ForEach(group.highlights) { highlight in
                                row(highlight, album: group.album)
                            }
                        } header: {
                            Label(group.album.title, systemImage: group.album.subject.symbol)
                                .foregroundStyle(group.album.subject.color)
                        }
                    }
                }
            }
        }
        .navigationTitle("Highlights")
    }

    private func row(_ highlight: CDAlbumHighlight, album: Album) -> some View {
        Button {
            nav.jump(albumID: highlight.albumID, pageIndex: Int(highlight.pageIndex))
        } label: {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(Album.highlightColor(highlight.colorName)))
                    .frame(width: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(highlight.text)
                        .font(.callout)
                        .lineLimit(3)
                    Text("\(highlight.lessonTitle) · p. \(Int(highlight.pageIndex) + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Remove Highlight", role: .destructive) {
                context.delete(highlight)
                context.safeSave()
            }
        }
        .swipeActions {
            Button("Remove", systemImage: "trash", role: .destructive) {
                context.delete(highlight)
                context.safeSave()
            }
        }
    }
}

struct AlbumNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    let note: CDAlbumPageNote
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Note — \(note.lessonTitle), p. \(Int(note.pageIndex) + 1)")
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary))
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    note.text = text
                    note.modifiedAt = Date()
                    context.safeSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 280)
        .onAppear { text = note.text }
    }
}
