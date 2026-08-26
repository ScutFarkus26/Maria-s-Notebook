// LessonAlbumMatcher.swift
// Joins the two halves of the app that have always described the same
// teaching but never knew about each other: `CDLesson`, the notebook's
// curriculum record, and `AlbumLessonRef`, an entry in a teaching album
// PDF's outline.
//
// Matching is scored, never assumed. Montessori albums repeat titles across
// levels — "Multiplication with the Checkerboard" appears in more than one
// sequence — so a wrong link is worse than no link. Only very strong matches
// auto-apply; everything else is a suggestion the guide accepts or rejects
// in `LessonAlbumMatchSheet`.

import CoreData
import Foundation
import OSLog

@MainActor
enum LessonAlbumMatcher {

    /// At or above this, a match is safe to apply without review.
    nonisolated static let autoLinkThreshold = 0.85
    /// Below this, a match isn't worth showing the guide at all.
    nonisolated static let suggestThreshold = 0.55

    // MARK: Candidate

    /// One proposed lesson ↔ album-page link, ready to show for review.
    struct Candidate: Identifiable, Sendable {
        var id: String { "\(lessonID.uuidString)|\(albumID)|\(pageIndex)" }
        let lessonID: UUID
        let lessonName: String
        let lessonArea: String
        let albumID: String
        let albumTitle: String
        let subject: AlbumSubject
        let pageIndex: Int
        let outlineTitle: String
        let score: Double

        var isConfident: Bool { score >= autoLinkThreshold }
    }

    /// The strongest album entry seen so far while scoring one lesson.
    private struct BestMatch {
        let album: Album
        let ref: AlbumLessonRef
        let score: Double
    }

    // MARK: Matching

    /// Scores every unlinked lesson against every album outline entry and
    /// returns the best candidate per lesson, strongest first.
    ///
    /// `library` must already be indexed — call `ensureIndexed()` first if
    /// there's any chance the guide hasn't opened the Albums section yet.
    static func candidates(for lessons: [CDLesson],
                           library: AlbumLibrary,
                           includeAlreadyLinked: Bool = false) async -> [Candidate] {
        let pending = lessons.filter { includeAlreadyLinked || $0.albumLink == nil }
        guard !pending.isEmpty, !library.albums.isEmpty else { return [] }

        var out: [Candidate] = []
        for lesson in pending {
            guard let lessonID = lesson.id else { continue }
            let name = lesson.name.trimmed()
            guard !name.isEmpty else { continue }

            // Semantic similarity is computed once per lesson against every
            // album, then combined with the cheap lexical score below.
            let vector = await library.semantic.queryVector(for: semanticQuery(for: lesson))

            var best: BestMatch?
            for album in library.albums {
                let subjectBonus = subjectAffinity(area: lesson.area, subject: album.subject)
                let similarities = vector.flatMap {
                    library.semantic.normalizedSimilarities(query: $0, albumID: album.id)
                }
                for (index, ref) in album.lessons.enumerated() {
                    let lexical: Double = titleSimilarity(name, ref.title)
                    var semantic = 0.0
                    if let similarities, similarities.indices.contains(index) {
                        semantic = Double(similarities[index])
                    }
                    // Title agreement is what actually identifies a lesson;
                    // meaning breaks ties and rescues differing wording.
                    let weighted: Double = (0.7 * lexical) + (0.3 * semantic) + subjectBonus
                    let score: Double = min(1.0, weighted)
                    if score > (best?.score ?? 0.0) {
                        best = BestMatch(album: album, ref: ref, score: score)
                    }
                }
            }

            guard let best, best.score >= suggestThreshold else { continue }
            out.append(Candidate(
                lessonID: lessonID,
                lessonName: lesson.name,
                lessonArea: lesson.area,
                albumID: best.album.id,
                albumTitle: best.album.title,
                subject: best.album.subject,
                pageIndex: best.ref.pageIndex,
                outlineTitle: best.ref.title,
                score: best.score))
        }
        return out.sorted { $0.score > $1.score }
    }

    // MARK: Applying

    /// Writes one accepted link.
    static func apply(_ candidate: Candidate, in context: NSManagedObjectContext) {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", candidate.lessonID as CVarArg)
        request.fetchLimit = 1
        guard let lesson = context.safeFetchFirst(request) else { return }
        lesson.albumLink = AlbumLink(albumID: candidate.albumID,
                                     pageIndex: candidate.pageIndex,
                                     lessonTitle: candidate.outlineTitle)
        lesson.albumLinkConfidence = candidate.score
    }

    /// Writes a batch of accepted links in one save.
    static func apply(_ candidates: [Candidate], in context: NSManagedObjectContext) {
        guard !candidates.isEmpty else { return }
        for candidate in candidates { apply(candidate, in: context) }
        context.safeSave()
    }

    /// Clears a lesson's link.
    static func unlink(_ lesson: CDLesson, in context: NSManagedObjectContext) {
        lesson.albumLink = nil
        context.safeSave()
    }

    // MARK: Re-resolution

    /// Re-points a lesson's page number after the guide drops in a revised
    /// PDF whose pagination has shifted. The outline title is the anchor;
    /// if it's gone, the existing page number is left alone rather than
    /// guessed at.
    @discardableResult
    static func reresolvePages(in album: Album, context: NSManagedObjectContext) -> Int {
        let lessons = CDLesson.lessonsInAlbum(album.id, context: context)
        guard !lessons.isEmpty else { return 0 }
        var moved = 0
        for lesson in lessons {
            guard let title = lesson.albumLessonTitle, !title.isEmpty else { continue }
            guard let ref = album.lessons.first(where: { $0.title == title }) else { continue }
            if Int(lesson.albumPageIndex) != ref.pageIndex {
                lesson.albumPageIndex = Int32(ref.pageIndex)
                moved += 1
            }
        }
        if moved > 0 {
            context.safeSave()
            Logger.albums.notice(
                "Re-resolved \(moved, privacy: .public) lesson link(s) in \(album.id, privacy: .public)")
        }
        return moved
    }

    // MARK: Scoring

    /// The text used to ask the semantic index what this lesson is about.
    private static func semanticQuery(for lesson: CDLesson) -> String {
        [lesson.name, lesson.purpose, String(lesson.writeUp.prefix(400))]
            .map { $0.trimmed() }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
    }

    /// A small nudge when the lesson's area agrees with the album's subject.
    /// Deliberately small: areas are free text and often don't line up.
    private static func subjectAffinity(area: String, subject: AlbumSubject) -> Double {
        guard subject != .other else { return 0 }
        let folded = AlbumLibrary.fold(area)
        return folded.contains(subject.rawValue) ? 0.08 : 0
    }

    /// 0…1 title agreement, tolerant of the punctuation, capitalisation, and
    /// filler words that differ between a guide's own naming and an album's
    /// outline ("The Checkerboard" vs "Checkerboard, Multiplication with").
    static func titleSimilarity(_ a: String, _ b: String) -> Double {
        let left = significantWords(a)
        let right = significantWords(b)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        if left == right { return 1 }
        let overlap = left.intersection(right).count
        guard overlap > 0 else { return 0 }
        // Dice coefficient — rewards agreement without punishing an album
        // outline entry for carrying extra qualifying words.
        return (2 * Double(overlap)) / Double(left.count + right.count)
    }

    private static let fillerWords: Set<String> = [
        "a", "an", "the", "of", "for", "with", "and", "to", "in", "on", "lesson", "presentation"
    ]

    private static func significantWords(_ s: String) -> Set<String> {
        let parts = AlbumLibrary.fold(s)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !fillerWords.contains($0) }
        return Set(parts)
    }
}
