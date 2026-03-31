import Foundation
import CoreData
import OSLog

// MARK: - CDResource & CDNoteStudentLink Import

extension BackupEntityImporter {

    // MARK: - CDResource

    static func importResources(
        _ dtos: [ResourceDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDResource>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: viewContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let r = CDResource(context: viewContext)
                r.id = dto.id
                r.title = dto.title
                r.descriptionText = dto.descriptionText
                r.categoryRaw = (ResourceCategory(rawValue: dto.categoryRaw) ?? .other).rawValue
                r.fileRelativePath = dto.fileRelativePath
                r.fileSizeBytes = dto.fileSizeBytes
                r.tags = dto.tags as NSArray
                r.isFavorite = dto.isFavorite
                r.linkedLessonIDs = dto.linkedLessonIDs
                r.linkedSubjects = dto.linkedSubjects
                r.lastViewedAt = dto.lastViewedAt
                r.createdAt = dto.createdAt
                r.modifiedAt = dto.modifiedAt
                return r
            })
    }

    // MARK: - CDNoteStudentLink

    static func importNoteStudentLinks(
        _ dtos: [NoteStudentLinkDTO],
        into viewContext: NSManagedObjectContext,
        existingCheck: EntityExistsCheck<CDNoteStudentLink>,
        noteCheck: EntityExistsCheck<CDNote>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let link = CDNoteStudentLink(context: viewContext)
            link.id = dto.id
            link.noteID = dto.noteID
            link.studentID = dto.studentID
            // Link to note if exists
            do {
                if let noteUUID = UUID(uuidString: dto.noteID),
                   let note = try noteCheck(noteUUID) {
                    link.note = note
                }
            } catch {
                Logger.backup.warning("Failed to check note for link: \(error.localizedDescription, privacy: .public)")
            }
            viewContext.insert(link)
        }
    }
}
