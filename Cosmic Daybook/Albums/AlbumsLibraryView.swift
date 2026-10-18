// AlbumsLibraryView.swift
// The home screen: a "Pick Up Where You Left Off" strip of recent lessons,
// then every album as a card with its real cover, lesson/page counts,
// bookmark badge, and "Updated" pill when the PDF changed on disk.
// Also hosts the shared snippet-highlighting helper used by search rows.

import CoreData
import SwiftUI
import UniformTypeIdentifiers

struct AlbumsLibraryView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumRecentVisit.visitedAt, ascending: false)
    ])
    private var recents: FetchedResults<CDAlbumRecentVisit>
    /// Fetched once for the whole grid — `AlbumCard` used to declare its own
    /// unfiltered fetch, so a shelf of N albums ran N full-table fetches.
    @FetchRequest(sortDescriptors: []) private var bookmarks: FetchedResults<CDAlbumBookmark>
    @State private var showFolderPicker = false
    @State private var showDataImporter = false
    @State private var importSummary: String?
    @State private var showMatchSheet = false

    private let columns = [GridItem(.adaptive(minimum: 185, maximum: 240), spacing: 18)]

    /// "1 album" / "3 albums" for the download line.
    private var pendingAlbumsPhrase: String {
        let count = library.pendingShelfAlbumNames.count
        return count == 1 ? "1 album" : "\(count) albums"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !recents.isEmpty {
                    continueSection
                }
                if !library.pendingShelfAlbumNames.isEmpty {
                    Label(
                        "Downloading \(pendingAlbumsPhrase) from iCloud…",
                        systemImage: "icloud.and.arrow.down"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                }
                ForEach(albumsWithNewerCopies) { album in
                    NewerCopyRow(album: album)
                }
                LazyVGrid(columns: columns, spacing: 18) {
                    ForEach(library.albums) { album in
                        AlbumCard(album: album, bookmarkCount: bookmarkCounts[album.id] ?? 0)
                    }
                }
            }
            .padding(20)
        }
        .navigationTitle("Library")
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Add Albums Folder…") { showFolderPicker = true }
                    if library.removableFolderURLs.count > 1
                        || (library.shelfURL != nil && !library.removableFolderURLs.isEmpty) {
                        Menu("Remove Folder") {
                            ForEach(library.removableFolderURLs, id: \.path) { url in
                                Button(url.lastPathComponent, role: .destructive) {
                                    library.removeFolder(url)
                                }
                            }
                        }
                    }
                    Button("Keep All Albums in iCloud") {
                        Task { await library.keepInICloud(library.albums) }
                    }
                    .disabled(!library.canKeepInICloud
                        || library.albums.allSatisfy { library.isKeptInICloud($0) })
                    Divider()
                    Button("Match Lessons to Albums…") { showMatchSheet = true }
                    Button("Refresh Album Search") { library.rebuildIndex() }
                    Divider()
                    Button("Import Albums App Data…") { showDataImporter = true }
                } label: {
                    Label("Library Options", systemImage: "ellipsis.circle")
                }
            }
        }
        .fileImporter(isPresented: $showFolderPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                library.chooseFolder(url)
            }
        }
        .sheet(isPresented: $showMatchSheet) {
            LessonAlbumMatchSheet(lessons: unlinkedLessons())
        }
        .fileImporter(isPresented: $showDataImporter, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result {
                importSummary = AlbumsDataImporter.importData(from: url, into: context)
            }
        }
        .alert("Couldn't Update iCloud Albums",
               isPresented: .init(get: { library.shelfError != nil },
                                  set: { if !$0 { library.shelfError = nil } })) {
            Button("OK") { library.shelfError = nil }
        } message: {
            Text(library.shelfError ?? "")
        }
        .alert("Import Albums App Data",
               isPresented: .init(get: { importSummary != nil },
                                  set: { if !$0 { importSummary = nil } })) {
            Button("OK") { importSummary = nil }
        } message: {
            Text(importSummary ?? "")
        }
    }

    /// Every notebook lesson that isn't linked to an album page yet.
    private func unlinkedLessons() -> [CDLesson] {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "albumID == nil OR albumID == %@", "")
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLesson.name, ascending: true)]
        return context.safeFetch(request)
    }

    /// Albums kept in iCloud whose original in a chosen folder has changed since.
    private var albumsWithNewerCopies: [Album] {
        library.albums.filter { library.newerCopy(for: $0) != nil }
    }

    /// Bookmark tallies keyed by album id, built in one pass over the fetch.
    private var bookmarkCounts: [String: Int] {
        bookmarks.reduce(into: [:]) { counts, bookmark in
            counts[bookmark.albumID, default: 0] += 1
        }
    }

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pick Up Where You Left Off")
                .font(.title3.bold())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(recents.prefix(8)), id: \.objectID) { visit in
                        AlbumRecentCard(visit: visit)
                    }
                }
            }
        }
    }
}

private struct AlbumRecentCard: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    let visit: CDAlbumRecentVisit

    var body: some View {
        let album = library.album(id: visit.albumID)
        Button {
            nav.jump(albumID: visit.albumID, pageIndex: Int(visit.pageIndex))
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Label(album?.title ?? Album.title(forID: visit.albumID),
                      systemImage: album?.subject.symbol ?? "doc.fill")
                    .font(.caption.bold())
                    .foregroundStyle(album?.subject.color ?? .gray)
                Text(visit.lessonTitle)
                    .font(.callout.weight(.medium))
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
                Text("p. \(Int(visit.pageIndex) + 1)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(width: 200, alignment: .leading)
            .background((album?.subject.color ?? .gray).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large))
        }
        .buttonStyle(.plain)
    }
}

private struct AlbumCard: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    @Environment(\.openWindow) private var openWindow
    let album: Album
    let bookmarkCount: Int
    @State private var confirmingRemoval = false
    /// How this device's chosen folders' copy compares with the one in
    /// iCloud, checked when Remove from iCloud is chosen: the dialog says
    /// what will happen.
    @State private var removal: AlbumICloudShelf.ChosenCopy = .missing
    @State private var confirmingNewerCopy = false
    @State private var newerCopyConfirmation = ""

    var body: some View {
        Button {
            nav.selection = .album(album.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(album.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("\(album.lessonCount) lessons · \(album.pageCount) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            #if os(macOS)
            Button("Open in New Window") {
                openWindow(id: "AlbumWindow", value: album.id)
            }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([album.url])
            }
            Button("Open in Preview") {
                NSWorkspace.shared.open(album.url)
            }
            Divider()
            #endif
            if library.isKeptInICloud(album) {
                if library.newerCopy(for: album) != nil {
                    Button("Use Newer Copy…", systemImage: "doc.badge.clock") {
                        newerCopyConfirmation = NewerCopyWording.confirmation(for: album, in: library)
                        confirmingNewerCopy = true
                    }
                    .disabled(library.albumsBeingKept.contains(album.id))
                }
                Button("Remove from iCloud…", systemImage: "icloud.slash", role: .destructive) {
                    removal = library.chosenCopy(of: album)
                    confirmingRemoval = true
                }
                .disabled(library.albumsBeingKept.contains(album.id))
            } else {
                Button("Keep in iCloud", systemImage: "icloud.and.arrow.up") {
                    Task { await library.keepInICloud([album]) }
                }
                .disabled(!library.canKeepInICloud || library.albumsBeingKept.contains(album.id))
            }
        }
        .confirmationDialog(
            "Remove \(album.title) from iCloud?",
            isPresented: $confirmingRemoval,
            titleVisibility: .visible
        ) {
            let deletes = removal.isCurrent
            Button(deletes ? "Remove from iCloud" : AlbumICloudShelf.moveToTrashTitle, role: .destructive) {
                Task { await library.removeFromICloud(album, mayDelete: deletes) }
            }
        } message: {
            Text(removalMessage)
        }
        .useNewerCopyConfirmation(album, isPresented: $confirmingNewerCopy, message: newerCopyConfirmation)
        // Keyed on whether the cover is loaded, so one dropped by a memory trim
        // comes back while the card is still on screen.
        .task(id: album.cover == nil) { library.loadCoverIfNeeded(album) }
    }

    /// What Remove from iCloud will do, for the dialog: delete it when a copy
    /// here is as new, otherwise move it to the Trash, saying why.
    private var removalMessage: String {
        let trash = AlbumICloudShelf.trashName
        switch removal {
        case .current:
            return "It will be deleted from iCloud Drive on every device. Your bookmarks and notes are kept, "
                + "and a copy in one of your own album folders will take its place."
        case .older(let copy):
            return "The copy in \(copy.deletingLastPathComponent().lastPathComponent) is older than the one "
                + "in iCloud, so the one in iCloud will be moved to \(trash) rather than deleted, and the older "
                + "copy will take its place. It leaves iCloud Drive on every device. "
                + "Your bookmarks and notes are kept."
        case .missing:
            return "There's no copy in this device's album folders, so it will be moved to \(trash) "
                + "rather than deleted. It leaves iCloud Drive on every device. "
                + "Your bookmarks and notes are kept."
        }
    }

    @ViewBuilder
    private var cover: some View {
        ZStack(alignment: .top) {
            Group {
                if let image = album.cover {
                    #if os(macOS)
                    Image(nsImage: image).resizable()
                    #else
                    Image(uiImage: image).resizable()
                    #endif
                } else {
                    ZStack {
                        album.subject.color.opacity(0.18)
                        Image(systemName: album.subject.symbol)
                            .font(.system(size: 42))
                            .foregroundStyle(album.subject.color)
                    }
                }
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipRounded(UIConstants.CornerRadius.control)
            .overlay(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.control).strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.12), radius: 5, y: 3)

            HStack {
                if library.albumsBeingKept.contains(album.id) {
                    ProgressView()
                        .controlSize(.small)
                        .padding(6)
                        .accessibilityLabel("Copying to iCloud")
                } else if library.isKeptInICloud(album) {
                    Image(systemName: "icloud.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(5)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(6)
                        .accessibilityLabel("Kept in iCloud")
                }
                if library.updatedAlbumIDs.contains(album.id) {
                    Text("Updated")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(.blue, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
                Spacer()
                if bookmarkCount > 0 {
                    Label("\(bookmarkCount)", systemImage: "bookmark.fill")
                        .font(.caption2.bold())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(album.subject.color, in: Capsule())
                        .foregroundStyle(.white)
                        .padding(6)
                }
            }
        }
    }
}
