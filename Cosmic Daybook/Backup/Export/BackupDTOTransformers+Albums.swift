import Foundation
import CoreData

// MARK: - Format v21 Transformers
//
// CD object -> DTO transformers for teaching-album annotations. Unlike the
// other features, two binary attributes are carried through: highlight
// rectangles (decoded to plain numbers) and PencilKit ink. Neither can be
// regenerated after a restore, so both belong in the archive.

extension BackupDTOTransformers {

    // MARK: - CDAlbumBookmark

    static func toDTO(_ bookmark: CDAlbumBookmark) -> AlbumBookmarkDTO {
        AlbumBookmarkDTO(
            id: bookmark.id ?? UUID(),
            albumID: bookmark.albumID,
            pageIndex: Int(bookmark.pageIndex),
            lessonTitle: bookmark.lessonTitle,
            createdAt: bookmark.createdAt ?? Date(),
            modifiedAt: bookmark.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ bookmarks: [CDAlbumBookmark]) -> [AlbumBookmarkDTO] {
        bookmarks.map { toDTO($0) }
    }

    // MARK: - CDAlbumPageNote

    static func toDTO(_ note: CDAlbumPageNote) -> AlbumPageNoteDTO {
        AlbumPageNoteDTO(
            id: note.id ?? UUID(),
            albumID: note.albumID,
            pageIndex: Int(note.pageIndex),
            lessonTitle: note.lessonTitle,
            text: note.text,
            createdAt: note.createdAt ?? Date(),
            modifiedAt: note.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ notes: [CDAlbumPageNote]) -> [AlbumPageNoteDTO] {
        notes.map { toDTO($0) }
    }

    // MARK: - CDAlbumRecentVisit

    static func toDTO(_ visit: CDAlbumRecentVisit) -> AlbumRecentVisitDTO {
        AlbumRecentVisitDTO(
            id: visit.id ?? UUID(),
            albumID: visit.albumID,
            pageIndex: Int(visit.pageIndex),
            lessonTitle: visit.lessonTitle,
            visitedAt: visit.visitedAt ?? Date(),
            modifiedAt: visit.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ visits: [CDAlbumRecentVisit]) -> [AlbumRecentVisitDTO] {
        visits.map { toDTO($0) }
    }

    // MARK: - CDAlbumReadingPosition

    static func toDTO(_ position: CDAlbumReadingPosition) -> AlbumReadingPositionDTO {
        AlbumReadingPositionDTO(
            id: position.id ?? UUID(),
            albumID: position.albumID,
            pageIndex: Int(position.pageIndex),
            modifiedAt: position.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ positions: [CDAlbumReadingPosition]) -> [AlbumReadingPositionDTO] {
        positions.map { toDTO($0) }
    }

    // MARK: - CDAlbumHighlight

    static func toDTO(_ highlight: CDAlbumHighlight) -> AlbumHighlightDTO {
        AlbumHighlightDTO(
            id: highlight.id ?? UUID(),
            albumID: highlight.albumID,
            pageIndex: Int(highlight.pageIndex),
            lessonTitle: highlight.lessonTitle,
            text: highlight.text,
            colorName: highlight.colorName,
            rects: highlight.rectValues,
            createdAt: highlight.createdAt ?? Date(),
            modifiedAt: highlight.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ highlights: [CDAlbumHighlight]) -> [AlbumHighlightDTO] {
        highlights.map { toDTO($0) }
    }

    // MARK: - CDAlbumPageInk

    static func toDTO(_ ink: CDAlbumPageInk) -> AlbumPageInkDTO {
        AlbumPageInkDTO(
            id: ink.id ?? UUID(),
            albumID: ink.albumID,
            pageIndex: Int(ink.pageIndex),
            drawingData: ink.drawingData ?? Data(),
            modifiedAt: ink.modifiedAt ?? Date()
        )
    }

    static func toDTOs(_ ink: [CDAlbumPageInk]) -> [AlbumPageInkDTO] {
        ink.map { toDTO($0) }
    }
}
