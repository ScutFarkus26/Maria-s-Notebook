// The Albums section's own sidebar: the fixed destinations with live counts,
// then one row per album with a dot when its PDF changed on disk.

import CoreData
import SwiftUI

struct AlbumsSidebar: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(\.openWindow) private var openWindow
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumBookmark.createdAt, ascending: false)
    ])
    private var bookmarks: FetchedResults<CDAlbumBookmark>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumPageNote.createdAt, ascending: false)
    ])
    private var notes: FetchedResults<CDAlbumPageNote>
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumHighlight.createdAt, ascending: false)
    ])
    private var highlights: FetchedResults<CDAlbumHighlight>
    @Binding var selection: AlbumsSidebarItem?

    var body: some View {
        List(selection: $selection) {
            Section {
                Label("Library", systemImage: "books.vertical.fill")
                    .tag(AlbumsSidebarItem.library)
                Label("Search", systemImage: "magnifyingglass")
                    .tag(AlbumsSidebarItem.search)
                Label("Ask the Albums", systemImage: "sparkles")
                    .tag(AlbumsSidebarItem.ask)
                Label("Bookmarks", systemImage: "bookmark.fill")
                    .badge(bookmarks.count)
                    .tag(AlbumsSidebarItem.bookmarks)
                Label("Notes", systemImage: "note.text")
                    .badge(notes.count)
                    .tag(AlbumsSidebarItem.notes)
                Label("Highlights", systemImage: "highlighter")
                    .badge(highlights.count)
                    .tag(AlbumsSidebarItem.highlights)
            }
            Section("Albums") {
                ForEach(library.albums) { album in
                    Label {
                        HStack(spacing: 5) {
                            Text(album.title)
                            if library.updatedAlbumIDs.contains(album.id) {
                                Circle()
                                    .fill(album.subject.color)
                                    .frame(width: 7, height: 7)
                                    .help("This album changed on disk")
                            }
                        }
                    } icon: {
                        Image(systemName: album.subject.symbol)
                            .foregroundStyle(album.subject.color)
                    }
                    .tag(AlbumsSidebarItem.album(album.id))
                    .contextMenu {
                        #if os(macOS)
                        Button("Open in New Window") {
                            openWindow(id: "AlbumWindow", value: album.id)
                        }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([album.url])
                        }
                        #endif
                    }
                }
            }
        }
        .navigationTitle("Albums")
        .safeAreaInset(edge: .bottom) {
            if library.indexing {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Indexing for search…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ProgressView(value: library.indexProgress)
                        .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.bar)
            }
        }
        #if os(macOS)
        .navigationSplitViewColumnWidth(min: 200, ideal: 225)
        #endif
    }
}
