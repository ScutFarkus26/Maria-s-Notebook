import Foundation

// Teaching-album annotations (format v21+).
//
// Note on binary data: the rest of the backup excludes binary attributes by
// design, because they are regenerable (thumbnails, covers, file bookmarks —
// see BackupTypes+V18Entities). Highlights and Pencil ink are the exception:
// nothing can recreate them, so losing them on restore would be real data
// loss. Highlight rectangles travel as plain numbers, and ink travels as its
// PencilKit drawing data.

// MARK: - Bookmarks, notes, visits, positions

nonisolated public struct AlbumBookmarkDTO: Codable, Sendable {
    public var id: UUID
    public var albumID: String
    public var pageIndex: Int
    public var lessonTitle: String
    public var createdAt: Date
    public var modifiedAt: Date
}

nonisolated public struct AlbumPageNoteDTO: Codable, Sendable {
    public var id: UUID
    public var albumID: String
    public var pageIndex: Int
    public var lessonTitle: String
    public var text: String
    public var createdAt: Date
    public var modifiedAt: Date
}

nonisolated public struct AlbumRecentVisitDTO: Codable, Sendable {
    public var id: UUID
    public var albumID: String
    public var pageIndex: Int
    public var lessonTitle: String
    public var visitedAt: Date
    public var modifiedAt: Date
}

nonisolated public struct AlbumReadingPositionDTO: Codable, Sendable {
    public var id: UUID
    public var albumID: String
    public var pageIndex: Int
    public var modifiedAt: Date
}

// MARK: - Highlights and ink

nonisolated public struct AlbumHighlightDTO: Codable, Sendable {
    public var id: UUID
    public var albumID: String
    public var pageIndex: Int
    public var lessonTitle: String
    public var text: String
    public var colorName: String
    /// Page-space rectangles as [x, y, width, height]. Decoded from the
    /// entity's JSON blob so the archive stays free of opaque binary.
    public var rects: [[Double]]
    public var createdAt: Date
    public var modifiedAt: Date
}

nonisolated public struct AlbumPageInkDTO: Codable, Sendable {
    public var id: UUID
    public var albumID: String
    public var pageIndex: Int
    /// PencilKit drawing data. Included deliberately — unlike thumbnails, ink
    /// is user-authored and cannot be regenerated.
    public var drawingData: Data
    public var modifiedAt: Date
}
