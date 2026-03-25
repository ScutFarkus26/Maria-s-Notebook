import Foundation
import SwiftData
import OSLog

// MARK: - Resource & NoteStudentLink Import

extension BackupEntityImporter {

    // MARK: - Resource

    static func importResources(
        _ dtos: [ResourceDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<Resource>
    ) rethrows {
        try importSimpleEntities(
            dtos, into: modelContext,
            existingCheck: existingCheck,
            idExtractor: { $0.id },
            entityBuilder: { dto in
                let r = Resource(
                    id: dto.id,
                    title: dto.title,
                    descriptionText: dto.descriptionText,
                    category: ResourceCategory(rawValue: dto.categoryRaw) ?? .other,
                    fileRelativePath: dto.fileRelativePath,
                    fileSizeBytes: dto.fileSizeBytes,
                    tags: dto.tags,
                    isFavorite: dto.isFavorite,
                    linkedLessonIDs: dto.linkedLessonIDs,
                    linkedSubjects: dto.linkedSubjects
                )
                r.lastViewedAt = dto.lastViewedAt
                r.createdAt = dto.createdAt
                r.modifiedAt = dto.modifiedAt
                return r
            })
    }

    // MARK: - NoteStudentLink

    static func importNoteStudentLinks(
        _ dtos: [NoteStudentLinkDTO],
        into modelContext: ModelContext,
        existingCheck: EntityExistsCheck<NoteStudentLink>,
        noteCheck: EntityExistsCheck<Note>
    ) rethrows {
        for dto in dtos {
            if shouldSkipExisting(id: dto.id, existingCheck: existingCheck) { continue }
            let link = NoteStudentLink(
                id: dto.id,
                noteID: dto.noteID,
                studentID: dto.studentID
            )
            // Link to note if exists
            do {
                if let noteUUID = UUID(uuidString: dto.noteID),
                   let note = try noteCheck(noteUUID) {
                    link.note = note
                }
            } catch {
                Logger.backup.warning("Failed to check note for link: \(error.localizedDescription, privacy: .public)")
            }
            modelContext.insert(link)
        }
    }
}
