import Foundation
import CoreData

// MARK: - Teaching-album annotation importers (format v21+)

extension BackupEntityImporter {

    // MARK: - CDAlbumBookmark

    static func importAlbumBookmarks(
        _ dtos: [AlbumBookmarkDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDAlbumBookmark>
    ) {
        for dto in dtos {
            // Skip records already in the store so a `.merge` restore doesn't insert duplicates.
            let entity = existingEntity(id: dto.id, existing: existing) ?? CDAlbumBookmark(context: viewContext)
            entity.id = dto.id
            entity.albumID = dto.albumID
            entity.pageIndex = Int32(dto.pageIndex)
            entity.lessonTitle = dto.lessonTitle
            entity.createdAt = dto.createdAt
            entity.modifiedAt = dto.modifiedAt
        }
    }

    // MARK: - CDAlbumPageNote

    static func importAlbumPageNotes(
        _ dtos: [AlbumPageNoteDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDAlbumPageNote>
    ) {
        for dto in dtos {
            let entity = existingEntity(id: dto.id, existing: existing) ?? CDAlbumPageNote(context: viewContext)
            entity.id = dto.id
            entity.albumID = dto.albumID
            entity.pageIndex = Int32(dto.pageIndex)
            entity.lessonTitle = dto.lessonTitle
            entity.text = dto.text
            entity.createdAt = dto.createdAt
            entity.modifiedAt = dto.modifiedAt
        }
    }

    // MARK: - CDAlbumRecentVisit

    static func importAlbumRecentVisits(
        _ dtos: [AlbumRecentVisitDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDAlbumRecentVisit>
    ) {
        for dto in dtos {
            let entity = existingEntity(id: dto.id, existing: existing) ?? CDAlbumRecentVisit(context: viewContext)
            entity.id = dto.id
            entity.albumID = dto.albumID
            entity.pageIndex = Int32(dto.pageIndex)
            entity.lessonTitle = dto.lessonTitle
            entity.visitedAt = dto.visitedAt
            entity.modifiedAt = dto.modifiedAt
        }
    }

    // MARK: - CDAlbumReadingPosition

    static func importAlbumReadingPositions(
        _ dtos: [AlbumReadingPositionDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDAlbumReadingPosition>
    ) {
        for dto in dtos {
            let entity = existingEntity(id: dto.id, existing: existing) ?? CDAlbumReadingPosition(context: viewContext)
            entity.id = dto.id
            entity.albumID = dto.albumID
            entity.pageIndex = Int32(dto.pageIndex)
            entity.modifiedAt = dto.modifiedAt
        }
    }

    // MARK: - CDAlbumHighlight

    static func importAlbumHighlights(
        _ dtos: [AlbumHighlightDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDAlbumHighlight>
    ) {
        for dto in dtos {
            let entity = existingEntity(id: dto.id, existing: existing) ?? CDAlbumHighlight(context: viewContext)
            entity.id = dto.id
            entity.albumID = dto.albumID
            entity.pageIndex = Int32(dto.pageIndex)
            entity.lessonTitle = dto.lessonTitle
            entity.text = dto.text
            entity.colorName = dto.colorName
            entity.setRectValues(dto.rects)
            entity.createdAt = dto.createdAt
            entity.modifiedAt = dto.modifiedAt
        }
    }

    // MARK: - CDAlbumPageInk

    static func importAlbumPageInk(
        _ dtos: [AlbumPageInkDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDAlbumPageInk>
    ) {
        for dto in dtos {
            let entity = existingEntity(id: dto.id, existing: existing) ?? CDAlbumPageInk(context: viewContext)
            entity.id = dto.id
            entity.albumID = dto.albumID
            entity.pageIndex = Int32(dto.pageIndex)
            entity.drawingData = dto.drawingData.isEmpty ? nil : dto.drawingData
            entity.modifiedAt = dto.modifiedAt
        }
    }
}
