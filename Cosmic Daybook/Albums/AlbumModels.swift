// The Albums feature's shared value types: subjects and their colors, outline
// and lesson references parsed from the PDFs, navigation targets, search
// results, and the focused-value plumbing that lets menu bar commands act on
// the frontmost album. Persistence lives in AlbumUserDataEntities.swift.

import SwiftUI

// MARK: - Subjects

nonisolated enum AlbumSubject: String, Codable, CaseIterable, Sendable {
    case art, biology, geography, geometry, history, language, math, music, theory, other

    static func detect(from title: String) -> AlbumSubject {
        let words = title.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
        for subject in AlbumSubject.allCases where subject != .other {
            if words.contains(subject.rawValue) { return subject }
        }
        return .other
    }

    var color: Color {
        switch self {
        case .art: .pink
        case .biology: .green
        case .geography: .blue
        case .geometry: .purple
        case .history: .orange
        case .language: .red
        case .math: .indigo
        case .music: .teal
        case .theory: .brown
        case .other: .gray
        }
    }

    var symbol: String {
        switch self {
        case .art: "paintpalette.fill"
        case .biology: "leaf.fill"
        case .geography: "globe.americas.fill"
        case .geometry: "triangle.fill"
        case .history: "hourglass"
        case .language: "textformat"
        case .math: "numbers.rectangle.fill"
        case .music: "music.note"
        case .theory: "book.fill"
        case .other: "doc.fill"
        }
    }
}

// MARK: - Outline

nonisolated struct AlbumOutlineNode: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let pageIndex: Int
    var children: [AlbumOutlineNode]?
}

/// A flattened outline entry, in document order. Used to map any page to its lesson.
nonisolated struct AlbumLessonRef: Identifiable, Hashable, Codable, Sendable {
    var id: String { "\(pageIndex)-\(title)" }
    let title: String
    let pageIndex: Int
    let depth: Int
}

// MARK: - Lesson links

/// Where one notebook lesson (`CDLesson`) is written up in a teaching album.
/// `lessonTitle` is the album's own outline title at that page, kept so the
/// link can be re-resolved by name when a revised PDF shifts pagination.
nonisolated struct AlbumLink: Equatable, Sendable {
    let albumID: String
    let pageIndex: Int
    var lessonTitle: String?
}

// MARK: - User data snapshots (Sendable copies for background search)

nonisolated struct AlbumNoteSnapshot: Identifiable, Sendable {
    let id: String
    let albumID: String
    let pageIndex: Int
    let lessonTitle: String
    let text: String
}

// MARK: - Navigation

enum AlbumsSidebarItem: Hashable {
    case library, search, ask, bookmarks, notes, highlights
    case album(String)

    /// Stable string form for scene restoration (@SceneStorage).
    var rawStorage: String {
        switch self {
        case .library: "library"
        case .search: "search"
        case .ask: "ask"
        case .bookmarks: "bookmarks"
        case .notes: "notes"
        case .highlights: "highlights"
        case .album(let id): "album:\(id)"
        }
    }

    init?(rawStorage: String) {
        switch rawStorage {
        case "library": self = .library
        case "search": self = .search
        case "ask": self = .ask
        case "bookmarks": self = .bookmarks
        case "notes": self = .notes
        case "highlights": self = .highlights
        default:
            guard rawStorage.hasPrefix("album:") else { return nil }
            self = .album(String(rawStorage.dropFirst("album:".count)))
        }
    }
}

nonisolated struct AlbumPageTarget: Equatable, Sendable {
    let id: UUID
    let albumID: String
    let pageIndex: Int
    var highlight: String?
}

/// A one-shot instruction for the PDF viewer to move to a page.
nonisolated struct AlbumPageJump: Equatable, Sendable {
    let id: UUID
    let pageIndex: Int
    var highlight: String?
}

// MARK: - Search

nonisolated struct AlbumSearchHit: Identifiable, Sendable {
    enum Kind: Sendable { case lesson, page, note }
    let id: String
    let kind: Kind
    let albumID: String
    let albumTitle: String
    let subject: AlbumSubject
    let pageIndex: Int
    let lessonTitle: String
    let snippet: String
    let score: Double
}

nonisolated struct AlbumSearchResults: Sendable {
    var query: String = ""
    var lessonHits: [AlbumSearchHit] = []
    var pageGroups: [(albumTitle: String, subject: AlbumSubject, hits: [AlbumSearchHit])] = []
    var noteHits: [AlbumSearchHit] = []
    /// Lessons found by meaning rather than keywords (semantic index).
    var semanticHits: [AlbumSearchHit] = []
    var isEmpty: Bool {
        lessonHits.isEmpty && pageGroups.isEmpty && noteHits.isEmpty && semanticHits.isEmpty
    }
    var totalCount: Int {
        lessonHits.count + pageGroups.reduce(0) { $0 + $1.hits.count } + noteHits.count
    }
}

// MARK: - Search corpus (immutable snapshot handed to background search)

nonisolated struct AlbumSearchCorpus: Sendable {
    struct AlbumData: Sendable {
        let id: String
        let title: String
        let subject: AlbumSubject
        let lessons: [AlbumLessonRef]
        /// Display text per page (ligatures normalized).
        let texts: [String]
        /// Case/diacritic-folded text per page, aligned with `texts`.
        let folded: [String]
    }
    var albums: [AlbumData] = []
}

// MARK: - Focused values (menu bar commands act on the active window)

/// Actions the frontmost album view exposes to the menu bar.
struct AlbumFocusActions {
    let albumID: String
    let toggleBookmark: () -> Void
    let addNote: () -> Void
    let nextPage: () -> Void
    let previousPage: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let actualSize: () -> Void
    let goToPage: () -> Void
    let printPDF: () -> Void
    let findInAlbum: () -> Void
    let highlightSelection: () -> Void
    let exportLesson: () -> Void
    let toggleThumbnails: () -> Void
}

extension FocusedValues {
    @Entry var albumActions: AlbumFocusActions?
    @Entry var albumsNav: AlbumsNavModel?
}

// MARK: - Ask (Apple Intelligence)

nonisolated struct AlbumAskSource: Identifiable, Sendable {
    let id: Int          // citation number, 1-based
    let albumID: String
    let albumTitle: String
    let lessonTitle: String
    let pageIndex: Int
}

nonisolated struct AlbumAskExchange: Identifiable, Sendable {
    let id = UUID()
    let question: String
    var answer: String?
    var sources: [AlbumAskSource] = []
    var error: String?
    var isRunning: Bool { answer == nil && error == nil }
}
