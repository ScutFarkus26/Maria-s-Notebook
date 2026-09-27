import Foundation
import CoreData
import OSLog

// MARK: - CDResource & CDNoteStudentLink Import

extension BackupEntityImporter {

    // MARK: - CDResource

    static func importResources(
        _ dtos: [ResourceDTO],
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<CDResource>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existing: existing,
            idExtractor: { $0.id },
            entityBuilder: { dto, current in
                let r = current ?? CDResource(context: viewContext)
                r.id = dto.id
                r.title = dto.title
                r.descriptionText = dto.descriptionText
                r.categoryRaw = (ResourceCategory(rawValue: dto.categoryRaw) ?? .other).rawValue
                r.fileRelativePath = dto.fileRelativePath
                r.fileSizeBytes = dto.fileSizeBytes
                r.tags = dto.tags as NSArray
                r.isFavorite = dto.isFavorite
                r.linkedLessonIDs = dto.linkedLessonIDs
                r.linkedAreas = dto.linkedAreas
                r.lastViewedAt = dto.lastViewedAt
                r.createdAt = dto.createdAt
                r.modifiedAt = dto.modifiedAt
                return r
            })
    }

}
