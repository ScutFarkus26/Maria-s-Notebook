// The three collection screens — Bookmarks, Notes, and Highlights — each
// grouped by album with jump-to-page rows, context menus, and swipe
// actions, plus the note editor sheet. All content comes from fetch
// requests, so edits made anywhere (including other devices) appear live.

import CoreData
import SwiftUI

/// One album's part of the Bookmarks, Notes or Highlights list. What the guide
/// saves syncs to every device, but an album's PDF may not be on this one: its
/// items still show, under the album's name, and can't be opened here. The
/// sidebar counts them all, so the screens list them all.
struct AlbumItemGroup<Item> {
    let albumID: String
    let title: String
    let subject: AlbumSubject
    /// Nil when the album isn't on this device.
    let album: Album?
    let items: [Item]

    /// Albums on this device in library order, then the others by name.
    static func groups(_ items: [Item], albumID: (Item) -> String, albums: [Album]) -> [AlbumItemGroup] {
        let byAlbum = Dictionary(grouping: items, by: albumID)
        let onDevice = albums.compactMap { album -> AlbumItemGroup? in
            guard let items = byAlbum[album.id] else { return nil }
            return AlbumItemGroup(albumID: album.id, title: album.title, subject: album.subject,
                                  album: album, items: items)
        }
        let loaded = Set(albums.map(\.id))
        let elsewhere = byAlbum.filter { !loaded.contains($0.key) }.map { id, items in
            let title = Album.title(forID: id)
            return AlbumItemGroup(albumID: id, title: title, subject: AlbumSubject.detect(from: title),
                                  album: nil, items: items)
        }
        return onDevice + elsewhere.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
}

/// A group's section header: the album's name and subject, and a note when
/// its PDF isn't on this device.
private struct AlbumItemGroupHeader<Item>: View {
    let group: AlbumItemGroup<Item>

    var body: some View {
        HStack {
            Label(group.title, systemImage: group.subject.symbol)
                .foregroundStyle(group.subject.color)
            if group.album == nil {
                Spacer()
                Text("Not on this device")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct AlbumBookmarksView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dependencies) private var dependencies
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumBookmark.albumID, ascending: true),
        NSSortDescriptor(keyPath: \CDAlbumBookmark.pageIndex, ascending: true)
    ])
    private var bookmarks: FetchedResults<CDAlbumBookmark>

    private var grouped: [AlbumItemGroup<CDAlbumBookmark>] {
        AlbumItemGroup.groups(Array(bookmarks), albumID: \.albumID, albums: library.albums)
    }

    var body: some View {
        Group {
            if bookmarks.isEmpty {
                ContentUnavailableView {
                    Label("No Bookmarks Yet", systemImage: "bookmark")
                } description: {
                    Text("While reading an album, press ⌘D or tap the bookmark button to save your place.")
                }
            } else {
                List {
                    ForEach(grouped, id: \.albumID) { group in
                        Section {
                            ForEach(group.items) { bookmark in
                                row(bookmark, in: group)
                            }
                        } header: {
                            AlbumItemGroupHeader(group: group)
                        }
                    }
                }
            }
        }
        .navigationTitle("Bookmarks")
    }

    private func row(_ bookmark: CDAlbumBookmark, in group: AlbumItemGroup<CDAlbumBookmark>) -> some View {
        Button {
            // An album that isn't on this device has nothing to open.
            guard group.album != nil else { return }
            nav.jump(albumID: bookmark.albumID, pageIndex: Int(bookmark.pageIndex))
        } label: {
            HStack {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(group.subject.color)
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
                dependencies.saveCoordinator.save(context, reason: "Remove bookmark")
            }
        }
        .swipeActions {
            Button("Remove", systemImage: "bookmark.slash", role: .destructive) {
                context.delete(bookmark)
                dependencies.saveCoordinator.save(context, reason: "Remove bookmark")
            }
        }
    }
}

struct AlbumNotesView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dependencies) private var dependencies
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumPageNote.albumID, ascending: true),
        NSSortDescriptor(keyPath: \CDAlbumPageNote.pageIndex, ascending: true),
        NSSortDescriptor(keyPath: \CDAlbumPageNote.createdAt, ascending: true)
    ])
    private var notes: FetchedResults<CDAlbumPageNote>
    @State private var editingNote: CDAlbumPageNote?

    private var grouped: [AlbumItemGroup<CDAlbumPageNote>] {
        AlbumItemGroup.groups(Array(notes), albumID: \.albumID, albums: library.albums)
    }

    var body: some View {
        Group {
            if notes.isEmpty {
                ContentUnavailableView {
                    Label("No Notes Yet", systemImage: "note.text")
                } description: {
                    Text("While reading, use the note button in the toolbar to attach thoughts "
                         + "to any page. They stay searchable forever.")
                }
            } else {
                List {
                    ForEach(grouped, id: \.albumID) { group in
                        Section {
                            ForEach(group.items) { note in
                                row(note, in: group)
                            }
                        } header: {
                            AlbumItemGroupHeader(group: group)
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

    private func row(_ note: CDAlbumPageNote, in group: AlbumItemGroup<CDAlbumPageNote>) -> some View {
        Button {
            guard group.album != nil else { return }
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
            Button("Delete Note", role: .destructive) {
                context.delete(note)
                dependencies.saveCoordinator.save(context, reason: "Delete note")
            }
        }
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) {
                context.delete(note)
                dependencies.saveCoordinator.save(context, reason: "Delete note")
            }
        }
    }
}

struct AlbumHighlightsView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dependencies) private var dependencies
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumHighlight.albumID, ascending: true),
        NSSortDescriptor(keyPath: \CDAlbumHighlight.pageIndex, ascending: true),
        NSSortDescriptor(keyPath: \CDAlbumHighlight.createdAt, ascending: true)
    ])
    private var highlights: FetchedResults<CDAlbumHighlight>

    private var grouped: [AlbumItemGroup<CDAlbumHighlight>] {
        AlbumItemGroup.groups(Array(highlights), albumID: \.albumID, albums: library.albums)
    }

    var body: some View {
        Group {
            if highlights.isEmpty {
                ContentUnavailableView {
                    Label("No Highlights Yet", systemImage: "highlighter")
                } description: {
                    Text("Select text in any album and press ⇧⌘H — or use the highlighter "
                         + "button — to mark passages worth returning to.")
                }
            } else {
                List {
                    ForEach(grouped, id: \.albumID) { group in
                        Section {
                            ForEach(group.items) { highlight in
                                row(highlight, in: group)
                            }
                        } header: {
                            AlbumItemGroupHeader(group: group)
                        }
                    }
                }
            }
        }
        .navigationTitle("Highlights")
    }

    private func row(_ highlight: CDAlbumHighlight, in group: AlbumItemGroup<CDAlbumHighlight>) -> some View {
        Button {
            guard group.album != nil else { return }
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
                dependencies.saveCoordinator.save(context, reason: "Remove highlight")
            }
        }
        .swipeActions {
            Button("Remove", systemImage: "trash", role: .destructive) {
                context.delete(highlight)
                dependencies.saveCoordinator.save(context, reason: "Remove highlight")
            }
        }
    }
}

struct AlbumNoteEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dependencies) private var dependencies
    let note: CDAlbumPageNote
    @State private var text = ""
    @State private var savedText = ""
    @State private var showingDiscardDialog = false
    /// Set once Save or Discard has decided. The sheet closes on the next
    /// update, when the dismissal question already knows not to ask: on the
    /// Mac a programmatic dismiss asks it too.
    @State private var isClosing = false

    private var hasUnsavedChanges: Bool { !isClosing && text != savedText }
    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Note — \(note.lessonTitle), p. \(Int(note.pageIndex) + 1)")
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .frame(minHeight: 160)
                .overlay(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium).strokeBorder(.quaternary))
            HStack {
                Spacer()
                Button("Cancel") {
                    if hasUnsavedChanges {
                        showingDiscardDialog = true
                    } else {
                        isClosing = true
                    }
                }
                Button("Save") {
                    save()
                    isClosing = true
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                // An emptied note is deleted from the list, not saved blank.
                .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 280)
        .onAppear {
            text = note.text
            savedText = note.text
        }
        .onChange(of: isClosing) {
            if isClosing { dismiss() }
        }
        // A swipe down (or, on the Mac, closing the sheet) asks before losing
        // what she typed.
        .dismissalConfirmationDialog("Save your changes to this note?", shouldPresent: hasUnsavedChanges) {
            if canSave {
                Button("Save") { save() }
            }
            Button("Discard Changes", role: .destructive) {}
            Button("Keep Editing", role: .cancel) {}
        }
        .confirmationDialog("Discard your changes to this note?", isPresented: $showingDiscardDialog,
                            titleVisibility: .visible) {
            Button("Discard Changes", role: .destructive) { isClosing = true }
            Button("Keep Editing", role: .cancel) {}
        }
    }

    private func save() {
        note.text = text
        note.modifiedAt = Date()
        dependencies.saveCoordinator.save(context, reason: "Save note")
        savedText = text
    }
}
