// AlbumTextFolds.swift
// The folded copy of each album's page text that search matches against,
// built off the main actor by the first search that needs it.

import Foundation

/// Each album's page text folded for matching (`String.folded()`: case and
/// diacritics dropped), page for page.
///
/// Nothing is folded until a search needs it. The first search after a load,
/// a trim, or a change to an album's text folds the albums it finds missing
/// off the main actor, side by side (`fold(_:albumID:)` takes and returns only
/// values); it used to fold them on the main actor, inside the search. A
/// search that arrives while an album is folding waits for that same fold
/// instead of starting another. A fold let go of while it runs (the album was
/// re-indexed, trimmed or purged) still answers the searches waiting on it,
/// with the text it folded, but isn't kept.
@MainActor
final class AlbumTextFolds {
    /// One album's page text with its fold, page for page.
    nonisolated struct Pages: Sendable, Equatable {
        let texts: [String]
        let folded: [String]
    }

    /// Where a search takes an album's fold from.
    private enum Source {
        case kept([String])
        case folding(Task<Pages, Never>)
    }

    /// A fold in progress. `number` tells it from a later fold of the same
    /// album, so a fold let go of while it ran is not kept.
    private struct Running {
        let number: Int
        let task: Task<Pages, Never>
    }

    /// Folds kept for later searches, by album id; each is the fold of that
    /// album's current page text.
    private(set) var kept: [String: [String]] = [:]
    private var running: [String: Running] = [:]
    private var foldsStarted = 0

    /// How many times a search found an album's fold running and waited for
    /// it instead of folding again (tests read this).
    private(set) var foldsJoined = 0

    /// Each album's page text with its fold, in the order given. Kept folds
    /// serve as they are, running ones are awaited, and the rest start now.
    /// An album with no page text (not indexed yet, or purged) has nothing to
    /// fold and gets nothing kept, as before: its text may be on its way.
    func pages(for albums: [(id: String, texts: [String])]) async -> [Pages] {
        // Every missing fold starts before any is awaited, so they run side by
        // side; kept ones are taken now, so a trim meanwhile can't take them away.
        let sources: [Source] = albums.map { album in
            if album.texts.isEmpty { return .kept([]) }
            if let folded = kept[album.id] { return .kept(folded) }
            return .folding(fold(album.id, texts: album.texts))
        }
        var pages: [Pages] = []
        pages.reserveCapacity(albums.count)
        for (album, source) in zip(albums, sources) {
            switch source {
            case .kept(let folded): pages.append(Pages(texts: album.texts, folded: folded))
            case .folding(let task): pages.append(await task.value)
            }
        }
        return pages
    }

    /// Lets go of an album's fold, kept or running: its page text changed.
    func drop(albumID: String) {
        kept[albumID] = nil
        running[albumID] = nil
    }

    /// Lets go of every fold, kept or running: a trim, memory pressure, or a
    /// rebuilt index.
    func dropAll() {
        kept.removeAll()
        running.removeAll()
    }

    /// The album's fold already running, or a new one.
    private func fold(_ albumID: String, texts: [String]) -> Task<Pages, Never> {
        if let fold = running[albumID] {
            foldsJoined += 1
            return fold.task
        }
        foldsStarted += 1
        let number = foldsStarted
        let task = Task {
            let pages = await Self.fold(texts, albumID: albumID)
            if self.running[albumID]?.number == number {
                self.running[albumID] = nil
                self.kept[albumID] = pages.folded
            }
            return pages
        }
        running[albumID] = Running(number: number, task: task)
        return task
    }

    /// Folds one album's page text, off the main actor.
    @concurrent
    nonisolated static func fold(_ texts: [String], albumID: String) async -> Pages {
        AlbumFoldProbe.reach("fold \(albumID)")
        return Pages(texts: texts, folded: texts.map { $0.folded() })
    }
}
