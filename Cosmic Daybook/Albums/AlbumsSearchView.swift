// AlbumsSearchView.swift
// Global search across every page of every album. Results come in four
// sections: lesson-title matches, page-content matches grouped by album
// (with highlighted snippets), matches in the user's own notes, and
// "Related by Meaning" — semantic matches that share no keywords with the
// query. Selecting a result jumps to the page with the match highlighted.

import CoreData
import SwiftUI

struct AlbumsSearchView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    @Environment(\.managedObjectContext) private var context

    @State private var query = ""
    @State private var albumFilter: String?
    @State private var results = AlbumSearchResults()
    @FocusState private var searchFocused: Bool

    private var terms: [String] { AlbumSearchEngine.tokens(for: results.query) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            resultsList
        }
        .navigationTitle("Search")
        .onAppear { searchFocused = true }
        .task(id: taskKey) { await runSearch() }
    }

    private var taskKey: String {
        query + "|" + (albumFilter ?? "all") + "|" + (library.indexing ? "i" : "r")
            + "|" + String(describing: library.semantic.status)
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search every page of every album…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Menu {
                    Button("All Albums") { albumFilter = nil }
                    Divider()
                    ForEach(library.albums) { album in
                        Button(album.title) { albumFilter = album.id }
                    }
                } label: {
                    Label(albumFilter.flatMap { library.album(id: $0)?.title } ?? "All Albums",
                          systemImage: "line.3.horizontal.decrease.circle")
                        .font(.callout)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .padding(12)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            if library.indexing {
                ProgressView(value: library.indexProgress) {
                    Text("Indexing pages… results may be incomplete")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .controlSize(.small)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var resultsList: some View {
        if query.trimmingCharacters(in: .whitespaces).count < 2 {
            ContentUnavailableView {
                Label("Search Your Albums", systemImage: "text.page.badge.magnifyingglass")
            } description: {
                Text("Every page of all \(library.albums.count) albums "
                     + "(\(library.indexedPageCount) pages) is indexed.\n"
                     + "Try a material, a lesson name, or any phrase — "
                     + "like “checkerboard” or “parts of the flower”.")
            }
        } else if results.isEmpty && results.query == query {
            ContentUnavailableView.search(text: query)
        } else {
            List {
                if !results.lessonHits.isEmpty {
                    Section("Lessons") {
                        ForEach(results.lessonHits) { hit in
                            lessonRow(hit)
                        }
                    }
                }
                ForEach(results.pageGroups, id: \.albumTitle) { group in
                    Section {
                        ForEach(group.hits) { hit in
                            pageRow(hit)
                        }
                    } header: {
                        Label(group.albumTitle, systemImage: group.subject.symbol)
                            .foregroundStyle(group.subject.color)
                    }
                }
                if !results.noteHits.isEmpty {
                    Section("Your Notes") {
                        ForEach(results.noteHits) { hit in
                            noteRow(hit)
                        }
                    }
                }
                if !results.semanticHits.isEmpty {
                    Section {
                        ForEach(results.semanticHits) { hit in
                            lessonRow(hit)
                        }
                    } header: {
                        Label("Related by Meaning", systemImage: "sparkles")
                    }
                }
            }
        }
    }

    private func lessonRow(_ hit: AlbumSearchHit) -> some View {
        Button {
            nav.jump(albumID: hit.albumID, pageIndex: hit.pageIndex)
        } label: {
            HStack {
                Image(systemName: hit.subject.symbol)
                    .foregroundStyle(hit.subject.color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text.albumHighlightedSnippet(hit.lessonTitle, terms: terms)
                        .font(.body.weight(.medium))
                    Text("\(hit.albumTitle) · p. \(hit.pageIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func pageRow(_ hit: AlbumSearchHit) -> some View {
        Button {
            nav.jump(albumID: hit.albumID, pageIndex: hit.pageIndex, highlight: results.query)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(hit.lessonTitle)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Text("p. \(hit.pageIndex + 1)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text.albumHighlightedSnippet(hit.snippet, terms: terms)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func noteRow(_ hit: AlbumSearchHit) -> some View {
        Button {
            nav.jump(albumID: hit.albumID, pageIndex: hit.pageIndex)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Image(systemName: "note.text")
                        .foregroundStyle(.yellow)
                    Text("\(hit.lessonTitle) · \(hit.albumTitle) · p. \(hit.pageIndex + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text.albumHighlightedSnippet(hit.snippet, terms: terms)
                    .font(.callout)
                    .lineLimit(3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = AlbumSearchResults()
            return
        }
        try? await Task.sleep(for: .milliseconds(140))
        guard !Task.isCancelled else { return }
        let corpus = library.corpus()
        let notes = AlbumUserDataStore.noteSnapshots(in: context)
        let filter = albumFilter
        var found = await Task.detached(priority: .userInitiated) {
            AlbumSearchEngine.search(query: trimmed, corpus: corpus, notes: notes, albumFilter: filter)
        }.value
        guard !Task.isCancelled else { return }
        found.semanticHits = await semanticHits(for: trimmed, keywordResults: found,
                                                albumFilter: filter)
        guard !Task.isCancelled else { return }
        results = found
    }

    /// Lessons that match the query by meaning, excluding anything the
    /// keyword search already surfaced.
    private func semanticHits(for query: String, keywordResults: AlbumSearchResults,
                              albumFilter: String?) async -> [AlbumSearchHit] {
        guard library.semantic.status == .ready,
              let queryVector = await library.semantic.queryVector(for: query) else { return [] }
        let alreadyShown = Set(keywordResults.lessonHits.map { "\($0.albumID)|\($0.pageIndex)" })
        let threshold = library.semantic.matchThreshold
        var hits: [AlbumSearchHit] = []
        for match in library.semantic.topMatches(query: queryVector, limit: 24) {
            guard match.score > threshold else { continue }
            if let filter = albumFilter, match.albumID != filter { continue }
            guard let album = library.album(id: match.albumID),
                  album.lessons.indices.contains(match.lessonIndex) else { continue }
            let lesson = album.lessons[match.lessonIndex]
            guard !alreadyShown.contains("\(album.id)|\(lesson.pageIndex)") else { continue }
            hits.append(AlbumSearchHit(
                id: "semantic-\(match.id)", kind: .lesson,
                albumID: album.id, albumTitle: album.title, subject: album.subject,
                pageIndex: lesson.pageIndex, lessonTitle: lesson.title,
                snippet: "", score: Double(match.score)))
            if hits.count >= 6 { break }
        }
        return hits
    }
}
