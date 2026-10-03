// AlbumSearchEngine.swift
// Keyword search and retrieval, pure functions safe to run off the main
// actor. `search` powers the Search screen (lesson-title hits ranked above
// page hits, snippets around the first match); `retrieve` picks the pages
// fed to Apple Intelligence for Ask, optionally boosted by semantic
// similarity from AlbumSemanticIndex.

import Foundation

nonisolated enum AlbumSearchEngine {

    static func tokens(for query: String) -> [String] {
        AlbumLibrary.normalize(query).folded()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: Full search (lessons, pages, notes)

    static func search(query: String, corpus: AlbumSearchCorpus, notes: [AlbumNoteSnapshot],
                       albumFilter: String?) -> AlbumSearchResults {
        let foldedQuery = AlbumLibrary.normalize(query).folded()
        let terms = tokens(for: query)
        guard !terms.isEmpty else { return AlbumSearchResults(query: query) }

        var results = AlbumSearchResults(query: query)
        let albums = corpus.albums.filter { albumFilter == nil || $0.id == albumFilter }

        results.lessonHits = lessonTitleHits(in: albums, terms: terms, foldedQuery: foldedQuery)
        results.pageGroups = pageContentGroups(in: albums, query: query, terms: terms,
                                               foldedQuery: foldedQuery)
        results.noteHits = noteHits(in: notes, corpus: corpus, terms: terms, albumFilter: albumFilter)
        return results
    }

    /// 1. Lesson-title hits — every term has to appear in the title; exact and
    /// prefix matches of the whole query rank above scattered ones, and shorter
    /// titles above longer ones.
    private static func lessonTitleHits(in albums: [AlbumSearchCorpus.AlbumData],
                                        terms: [String], foldedQuery: String) -> [AlbumSearchHit] {
        var lessonHits: [AlbumSearchHit] = []
        for album in albums {
            for lesson in album.lessons {
                let folded = lesson.title.folded()
                guard terms.allSatisfy({ folded.contains($0) }) else { continue }
                var score = 100.0
                if folded.contains(foldedQuery) { score += 40 }
                if folded.hasPrefix(foldedQuery) { score += 30 }
                score -= Double(folded.count) * 0.1
                lessonHits.append(AlbumSearchHit(
                    id: "lesson-\(album.id)-\(lesson.id)", kind: .lesson,
                    albumID: album.id, albumTitle: album.title, subject: album.subject,
                    pageIndex: lesson.pageIndex, lessonTitle: lesson.title,
                    snippet: "", score: score))
            }
        }
        return Array(lessonHits.sorted { $0.score > $1.score }.prefix(12))
    }

    /// 2. Page-content hits, grouped by album and ordered by their best hit.
    private static func pageContentGroups(in albums: [AlbumSearchCorpus.AlbumData], query: String,
                                          terms: [String], foldedQuery: String) -> [AlbumPageGroup] {
        var groups: [AlbumPageGroup] = []
        for album in albums {
            let hits = pageHits(in: album, query: query, terms: terms, foldedQuery: foldedQuery)
            if !hits.isEmpty {
                groups.append(AlbumPageGroup(albumTitle: album.title, subject: album.subject,
                                             hits: Array(hits.prefix(8))))
            }
        }
        groups.sort { ($0.hits.first?.score ?? 0) > ($1.hits.first?.score ?? 0) }
        return groups
    }

    /// Every matching page of one album, best score first.
    private static func pageHits(in album: AlbumSearchCorpus.AlbumData, query: String,
                                 terms: [String], foldedQuery: String) -> [AlbumSearchHit] {
        var hits: [AlbumSearchHit] = []
        for (pageIndex, folded) in album.folded.enumerated() {
            guard !folded.isEmpty else { continue }
            guard var score = keywordScore(in: folded, terms: terms, foldedQuery: foldedQuery) else {
                continue
            }
            let lesson = album.lessons.last { $0.pageIndex <= pageIndex }
            if let lesson {
                let lessonFolded = lesson.title.folded()
                if terms.contains(where: { lessonFolded.contains($0) }) { score += 20 }
            }
            let snippet = snippet(in: album.texts[pageIndex], query: query, terms: terms)
            hits.append(AlbumSearchHit(
                id: "page-\(album.id)-\(pageIndex)", kind: .page,
                albumID: album.id, albumTitle: album.title, subject: album.subject,
                pageIndex: pageIndex, lessonTitle: lesson?.title ?? album.title,
                snippet: snippet, score: score))
        }
        hits.sort { $0.score > $1.score }
        return hits
    }

    /// Term-frequency score for one page, or `nil` when the page is missing any
    /// of the terms. The whole-query bonus only applies to multi-term queries —
    /// a single term already scored above.
    private static func keywordScore(in folded: String, terms: [String],
                                     foldedQuery: String) -> Double? {
        var score = 0.0
        for term in terms {
            let count = occurrences(of: term, in: folded, cap: 12)
            if count == 0 { return nil }
            score += Double(count) * 3
        }
        if terms.count > 1, folded.contains(foldedQuery) { score += 30 }
        return score
    }

    /// 3. Note hits — the guide's own notes, searched over their text plus the
    /// lesson they were written against.
    private static func noteHits(in notes: [AlbumNoteSnapshot], corpus: AlbumSearchCorpus,
                                 terms: [String], albumFilter: String?) -> [AlbumSearchHit] {
        let albumTitles = Dictionary(uniqueKeysWithValues: corpus.albums.map { ($0.id, ($0.title, $0.subject)) })
        var hits: [AlbumSearchHit] = []
        for note in notes {
            if let filter = albumFilter, note.albumID != filter { continue }
            let folded = (note.text + " " + note.lessonTitle).folded()
            guard terms.allSatisfy({ folded.contains($0) }) else { continue }
            let (title, subject) = albumTitles[note.albumID] ?? (note.albumID, .other)
            hits.append(AlbumSearchHit(
                id: "note-\(note.id)", kind: .note,
                albumID: note.albumID, albumTitle: title, subject: subject,
                pageIndex: note.pageIndex, lessonTitle: note.lessonTitle,
                snippet: String(note.text.prefix(160)), score: 50))
        }
        return hits
    }

    private static func occurrences(of term: String, in text: String, cap: Int) -> Int {
        var count = 0
        var start = text.startIndex
        while count < cap, let range = text.range(of: term, range: start..<text.endIndex) {
            count += 1
            start = range.upperBound
        }
        return count
    }

    /// A short window of the original page text around the first match.
    static func snippet(in text: String, query: String, terms: [String]) -> String {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let matchRange = text.range(of: query.trimmingCharacters(in: .whitespacesAndNewlines), options: options)
            ?? terms.lazy.compactMap { text.range(of: $0, options: options) }.first
        guard let matchRange else { return String(text.prefix(160)) }

        let lower = text.index(matchRange.lowerBound, offsetBy: -110,
                               limitedBy: text.startIndex) ?? text.startIndex
        let upper = text.index(matchRange.upperBound, offsetBy: 140,
                               limitedBy: text.endIndex) ?? text.endIndex
        var out = String(text[lower..<upper])
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if lower > text.startIndex { out = "…" + out }
        if upper < text.endIndex { out += "…" }
        return out
    }

    // MARK: Retrieval for Ask (question → most relevant pages)

    /// One album page with the score retrieval gave it.
    struct ScoredPage: Sendable {
        let album: AlbumSearchCorpus.AlbumData
        let pageIndex: Int
        let score: Double
    }

    static let stopwords: Set<String> = [
        "the", "a", "an", "and", "or", "of", "to", "in", "on", "for", "with", "at", "by",
        "is", "are", "was", "were", "be", "been", "do", "does", "did", "can", "could",
        "how", "what", "when", "where", "which", "who", "why", "should", "would",
        "i", "my", "me", "we", "our", "you", "your", "it", "its", "this", "that", "there",
        "about", "into", "from", "as", "not", "no", "if", "then", "than", "so",
        "lesson", "lessons", "present", "presented", "presentation", "teach", "child", "children"
    ]

    /// `boost` carries per-lesson semantic similarity scores (albumID →
    /// one score per Album.lessons entry); pages inherit their lesson's
    /// score so meaning-based matches surface even without keyword overlap.
    static func retrieve(question: String, corpus: AlbumSearchCorpus, limit: Int,
                         boost: [String: [Float]]? = nil) -> [ScoredPage] {
        var terms = tokens(for: question).filter { $0.count > 2 && !stopwords.contains($0) }
        if terms.isEmpty { terms = tokens(for: question) }
        guard !terms.isEmpty else { return [] }

        var scored = scoredPages(in: corpus, terms: terms, boost: boost)
        scored.sort { $0.score > $1.score }
        return pickVariedSources(from: scored, limit: limit)
    }

    /// Every page that clears the keyword-or-meaning floor, unsorted.
    private static func scoredPages(in corpus: AlbumSearchCorpus, terms: [String],
                                    boost: [String: [Float]]?) -> [ScoredPage] {
        var scored: [ScoredPage] = []
        for album in corpus.albums {
            let albumBoost = boost?[album.id]
            for (pageIndex, folded) in album.folded.enumerated() {
                guard !folded.isEmpty else { continue }
                guard let score = retrievalScore(in: album, pageIndex: pageIndex, folded: folded,
                                                 terms: terms, albumBoost: albumBoost) else { continue }
                scored.append(ScoredPage(album: album, pageIndex: pageIndex, score: score))
            }
        }
        return scored
    }

    /// Score for one page, or `nil` when neither keywords nor meaning reach it.
    private static func retrievalScore(in album: AlbumSearchCorpus.AlbumData, pageIndex: Int,
                                       folded: String, terms: [String],
                                       albumBoost: [Float]?) -> Double? {
        var score = 0.0
        var found = 0
        for term in terms {
            let count = occurrences(of: term, in: folded, cap: 8)
            if count > 0 { found += 1; score += Double(count) }
        }
        let lessonIndex = album.lessons.lastIndex { $0.pageIndex <= pageIndex }
        var semantic = 0.0
        if let albumBoost, let lessonIndex, albumBoost.indices.contains(lessonIndex) {
            semantic = Double(albumBoost[lessonIndex])
        }
        // `semantic` is on the normalized 0…1 scale (0 = noise floor).
        guard found > 0 || semantic > 0.1 else { return nil }
        // Strongly prefer pages containing more of the distinct terms.
        score += Double(found * found) * 10
        score += semantic * 60
        if let lessonIndex {
            let lessonFolded = album.lessons[lessonIndex].title.folded()
            let inTitle = terms.filter { lessonFolded.contains($0) }.count
            score += Double(inTitle) * 25
        }
        return score
    }

    /// Keeps the best pages, at most two per lesson so sources stay varied.
    private static func pickVariedSources(from scored: [ScoredPage], limit: Int) -> [ScoredPage] {
        var picked: [ScoredPage] = []
        var perLesson: [String: Int] = [:]
        for entry in scored {
            let lesson = entry.album.lessons.last { $0.pageIndex <= entry.pageIndex }
            let key = "\(entry.album.id)|\(lesson?.title ?? "")"
            if perLesson[key, default: 0] >= 2 { continue }
            perLesson[key, default: 0] += 1
            picked.append(entry)
            if picked.count >= limit { break }
        }
        return picked
    }
}
