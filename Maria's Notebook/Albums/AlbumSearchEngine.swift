// AlbumSearchEngine.swift
// Keyword search and retrieval, pure functions safe to run off the main
// actor. `search` powers the Search screen (lesson-title hits ranked above
// page hits, snippets around the first match); `retrieve` picks the pages
// fed to Apple AlbumIntelligence for Ask, optionally boosted by semantic
// similarity from AlbumSemanticIndex.

import Foundation

nonisolated enum AlbumSearchEngine {

    static func tokens(for query: String) -> [String] {
        AlbumLibrary.fold(AlbumLibrary.normalize(query))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    // MARK: Full search (lessons, pages, notes)

    static func search(query: String, corpus: AlbumSearchCorpus, notes: [AlbumNoteSnapshot],
                       albumFilter: String?) -> AlbumSearchResults {
        let foldedQuery = AlbumLibrary.fold(AlbumLibrary.normalize(query))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = tokens(for: query)
        guard !terms.isEmpty else { return AlbumSearchResults(query: query) }

        var results = AlbumSearchResults(query: query)
        let albums = corpus.albums.filter { albumFilter == nil || $0.id == albumFilter }

        // 1. Lesson-title hits
        var lessonHits: [AlbumSearchHit] = []
        for album in albums {
            for lesson in album.lessons {
                let folded = AlbumLibrary.fold(lesson.title)
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
        results.lessonHits = Array(lessonHits.sorted { $0.score > $1.score }.prefix(12))

        // 2. Page-content hits, grouped by album
        for album in albums {
            var hits: [AlbumSearchHit] = []
            for (pageIndex, folded) in album.folded.enumerated() {
                guard !folded.isEmpty else { continue }
                var score = 0.0
                var allFound = true
                for term in terms {
                    let count = occurrences(of: term, in: folded, cap: 12)
                    if count == 0 { allFound = false; break }
                    score += Double(count) * 3
                }
                guard allFound else { continue }
                if terms.count > 1, folded.contains(foldedQuery) { score += 30 }
                let lesson = album.lessons.last { $0.pageIndex <= pageIndex }
                if let lesson {
                    let lessonFolded = AlbumLibrary.fold(lesson.title)
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
            if !hits.isEmpty {
                results.pageGroups.append((album.title, album.subject, Array(hits.prefix(8))))
            }
        }
        results.pageGroups.sort { ($0.hits.first?.score ?? 0) > ($1.hits.first?.score ?? 0) }

        // 3. Note hits
        let albumTitles = Dictionary(uniqueKeysWithValues: corpus.albums.map { ($0.id, ($0.title, $0.subject)) })
        for note in notes {
            if let filter = albumFilter, note.albumID != filter { continue }
            let folded = AlbumLibrary.fold(note.text + " " + note.lessonTitle)
            guard terms.allSatisfy({ folded.contains($0) }) else { continue }
            let (title, subject) = albumTitles[note.albumID] ?? (note.albumID, .other)
            results.noteHits.append(AlbumSearchHit(
                id: "note-\(note.id)", kind: .note,
                albumID: note.albumID, albumTitle: title, subject: subject,
                pageIndex: note.pageIndex, lessonTitle: note.lessonTitle,
                snippet: String(note.text.prefix(160)), score: 50))
        }

        return results
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
                         boost: [String: [Float]]? = nil)
        -> [(album: AlbumSearchCorpus.AlbumData, pageIndex: Int, score: Double)] {
        var terms = tokens(for: question).filter { $0.count > 2 && !stopwords.contains($0) }
        if terms.isEmpty { terms = tokens(for: question) }
        guard !terms.isEmpty else { return [] }

        var scored: [(album: AlbumSearchCorpus.AlbumData, pageIndex: Int, score: Double)] = []
        for album in corpus.albums {
            let albumBoost = boost?[album.id]
            for (pageIndex, folded) in album.folded.enumerated() {
                guard !folded.isEmpty else { continue }
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
                guard found > 0 || semantic > 0.1 else { continue }
                // Strongly prefer pages containing more of the distinct terms.
                score += Double(found * found) * 10
                score += semantic * 60
                if let lessonIndex {
                    let lessonFolded = AlbumLibrary.fold(album.lessons[lessonIndex].title)
                    let inTitle = terms.filter { lessonFolded.contains($0) }.count
                    score += Double(inTitle) * 25
                }
                scored.append((album, pageIndex, score))
            }
        }
        scored.sort { $0.score > $1.score }

        // Keep the best pages, at most two per lesson so sources stay varied.
        var picked: [(album: AlbumSearchCorpus.AlbumData, pageIndex: Int, score: Double)] = []
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
