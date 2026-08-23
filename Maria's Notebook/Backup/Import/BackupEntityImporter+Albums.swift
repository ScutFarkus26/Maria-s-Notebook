import Foundation
import CoreData

// MARK: - Teaching-album annotation importers (format v21+)

extension BackupEntityImporter {

    // MARK: - CDAlbumBookmark

    static func importAlbumBookmarks(
        _ dtos: [AlbumBookmarkDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck
    ) {
        for dto in dtos {
            // Skip records already in the store so a `.merge` restore doesn't insert duplicates.
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let entity = CDAlbumBookmark(context: viewContext)
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
        existingCheck: EntityExistsCheck
    ) {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let entity = CDAlbumPageNote(context: viewContext)
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
        existingCheck: EntityExistsCheck
    ) {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let entity = CDAlbumRecentVisit(context: viewContext)
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
        existingCheck: EntityExistsCheck
    ) {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let entity = CDAlbumReadingPosition(context: viewContext)
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
        existingCheck: EntityExistsCheck
    ) {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let entity = CDAlbumHighlight(context: viewContext)
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
        existingCheck: EntityExistsCheck
    ) {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let entity = CDAlbumPageInk(context: viewContext)
            entity.id = dto.id
            entity.albumID = dto.albumID
            entity.pageIndex = Int32(dto.pageIndex)
            entity.drawingData = dto.drawingData.isEmpty ? nil : dto.drawingData
            entity.modifiedAt = dto.modifiedAt
        }
    }
}
