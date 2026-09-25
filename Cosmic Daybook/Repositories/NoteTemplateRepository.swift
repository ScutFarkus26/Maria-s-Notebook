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

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a NoteTemplate by ID
    func fetchTemplate(id: UUID) -> CDNoteTemplate? { fetch(id: id) }

    /// Fetch multiple NoteTemplates with optional filtering and sorting
    func fetchTemplates(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "sortOrder", ascending: true)]
    ) -> [CDNoteTemplate] {
        let request = CDFetchRequest(CDNoteTemplate.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    /// Fetch only built-in templates
    func fetchBuiltInTemplates() -> [CDNoteTemplate] {
        fetchTemplates(predicate: NSPredicate(format: "isBuiltIn == YES"))
    }

    // MARK: - Delete

    /// Delete a NoteTemplate by ID (only custom templates can be deleted)
    func deleteTemplate(id: UUID) throws {
        guard let template = fetchTemplate(id: id) else { return }
        guard !template.isBuiltIn else { return }
        context.delete(template)
        try context.save()
    }
}
