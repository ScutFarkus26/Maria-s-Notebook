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
    @Environment(AlbumsNavModel.self) private var nav
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !recents.isEmpty {
                    continueSection
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
                    if library.folderURLs.count > 1 {
                        Menu("Remove Folder") {
                            ForEach(library.folderURLs, id: \.path) { url in
                                Button(url.lastPathComponent, role: .destructive) {
                                    library.removeFolder(url)
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Match Lessons to Albums…") { showMatchSheet = true }
                    Button("Rebuild Search Index") { library.rebuildIndex() }
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
                Label(album?.title ?? visit.albumID,
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
                        in: RoundedRectangle(cornerRadius: 12))
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
            #endif
        }
        .task { library.loadCoverIfNeeded(album) }
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
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
            .shadow(color: .black.opacity(0.12), radius: 5, y: 3)

            HStack {
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

// MARK: - Shared snippet highlighting

extension Text {
    /// Renders a snippet with the query terms emphasized.
    static func albumHighlightedSnippet(_ snippet: String, terms: [String]) -> Text {
        var attributed = AttributedString(snippet)
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        for term in terms where !term.isEmpty {
            var searchStart = snippet.startIndex
            while let range = snippet.range(of: term, options: options,
                                            range: searchStart..<snippet.endIndex) {
                if let attrRange = Range(range, in: attributed) {
                    attributed[attrRange].font = .callout.bold()
                    attributed[attrRange].foregroundColor = .accentColor
                }
                searchStart = range.upperBound
            }
        }
        return Text(attributed)
    }
}
