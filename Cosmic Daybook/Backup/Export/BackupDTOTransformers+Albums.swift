import Foundation
import CoreData

// MARK: - Format v21 Transformers
//
// CD object -> DTO transformers for teaching-album annotations. Unlike the
// other features, two binary attributes are carried through: highlight
// rectangles (decoded to plain numbers) and PencilKit ink. Neither can be
// regenerated after a restore, so both belong in the archive.

extension BackupDTOTransformers {

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
