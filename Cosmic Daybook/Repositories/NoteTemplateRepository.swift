//
//  NoteTemplateRepository.swift
//  Cosmic Daybook
//
//  Repository for NoteTemplate entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

struct NoteTemplateRepository: SavingRepository {
    typealias Model = CDNoteTemplate

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a NoteTemplate by ID
    func fetchTemplate(id: UUID) -> CDNoteTemplate? { fetch(id: id) }

    // MARK: - Delete

    /// Delete a NoteTemplate by ID (only custom templates can be deleted)
    func deleteTemplate(id: UUID) throws {
        guard let template = fetchTemplate(id: id) else { return }
        guard !template.isBuiltIn else { return }
        context.delete(template)
        try context.save()
    }
}
