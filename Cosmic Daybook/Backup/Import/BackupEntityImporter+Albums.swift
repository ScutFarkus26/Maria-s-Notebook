import Foundation
import CoreData

// MARK: - Teaching-album annotation importers (format v21+)

extension BackupEntityImporter {

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
