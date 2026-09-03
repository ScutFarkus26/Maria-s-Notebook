// The album corpus as the assistants see it. Both the on-device chat tool
// (Services/AI/NotebookTools.swift) and the MCP server's read tools
// (Services/MCPServer/MCPNotebookTools+Reads.swift) go through here, so the
// two surfaces return the same wording and the same citation format.
//
// Album pages have no UUID, so citations name the album file and page number
// instead of the `[kind id=<uuid>]` form the notebook entities use. A caller
// can follow one up with `page(album:page:)` for the full text.

import Foundation

nonisolated enum AlbumCorpusLookup {

    /// One retrieved album page, ready to hand to a model.
    struct Hit: Sendable {
        let albumID: String
        let albumTitle: String
        let lessonTitle: String
        /// Zero-based, as stored; `citationLine` prints it one-based.
        let pageIndex: Int
        let snippet: String

        var citationLine: String {
            "- [albumPage album=\"\(albumID)\" page=\(pageIndex + 1)] "
                + "\(albumTitle) · \"\(lessonTitle)\" (p. \(pageIndex + 1)): \(snippet)"
        }
    }

    /// Searches every page of every album, boosted by the semantic index so a
    /// query like "borrowing" reaches lessons that never use the word.
    static func search(query: String, limit: Int) async -> [Hit] {
        let library = await AlbumLibrary.shared
        await library.ensureIndexed()

        let corpus = await MainActor.run { library.corpus() }
        guard !corpus.albums.isEmpty else { return [] }

        let boost = await semanticBoost(for: query, corpus: corpus, library: library)
        let picks = await Task.detached(priority: .userInitiated) {
            AlbumSearchEngine.retrieve(question: query, corpus: corpus, limit: limit, boost: boost)
        }.value

        return picks.map { pick in
            let lesson = pick.album.lessons.last { $0.pageIndex <= pick.pageIndex }
            let text = pick.album.texts[pick.pageIndex]
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Hit(albumID: pick.album.id,
                       albumTitle: pick.album.title,
                       lessonTitle: lesson?.title ?? pick.album.title,
                       pageIndex: pick.pageIndex,
                       snippet: String(text.prefix(300)))
        }
    }

    /// The full text of one album page, so a model can follow a citation.
    static func page(album albumID: String, page oneBasedPage: Int) async -> String? {
        let library = await AlbumLibrary.shared
        await library.ensureIndexed()
        return await MainActor.run {
            library.text(albumID: albumID, pageIndex: oneBasedPage - 1)
        }
    }

    /// Explains an empty result — usually "no albums set up yet" rather than
    /// "nothing matched", and the two need different follow-up from the guide.
    static func emptyResultMessage(for query: String) async -> String {
        let hasAlbums = await MainActor.run { !AlbumLibrary.shared.albums.isEmpty }
        guard hasAlbums else {
            return "No teaching albums are set up yet. Open Albums in the sidebar and choose "
                + "the folder holding the album PDFs."
        }
        return "Nothing in the teaching albums matched \"\(query)\"."
    }

    // MARK: Semantic boost

    private static func semanticBoost(for query: String,
                                      corpus: AlbumSearchCorpus,
                                      library: AlbumLibrary) async -> [String: [Float]]? {
        let ready = await MainActor.run { library.semantic.status == .ready }
        guard ready, let vector = await library.semantic.queryVector(for: query) else { return nil }
        return await MainActor.run {
            var boost: [String: [Float]] = [:]
            for album in corpus.albums {
                boost[album.id] = library.semantic.normalizedSimilarities(query: vector,
                                                                         albumID: album.id)
            }
            return boost
        }
    }
}
