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
    typealias Model = CDNoteTemplateEntity

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a NoteTemplate by ID
    func fetchTemplate(id: UUID) -> CDNoteTemplateEntity? { fetch(id: id) }

    /// Fetch multiple NoteTemplates with optional filtering and sorting
    func fetchTemplates(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "sortOrder", ascending: true)]
    ) -> [CDNoteTemplateEntity] {
        let request = CDFetchRequest(CDNoteTemplateEntity.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    /// Fetch only built-in templates
    func fetchBuiltInTemplates() -> [CDNoteTemplateEntity] {
        fetchTemplates(predicate: NSPredicate(format: "isBuiltIn == YES"))
    }

    /// Fetch only custom (user-created) templates
    func fetchCustomTemplates() -> [CDNoteTemplateEntity] {
        fetchTemplates(predicate: NSPredicate(format: "isBuiltIn == NO"))
    }

    // MARK: - Update

    /// Reorder custom templates by updating their sort orders
    @discardableResult
    func reorderTemplates(ids: [UUID]) -> Bool {
        for (index, id) in ids.enumerated() {
            guard let template = fetchTemplate(id: id) else { continue }
            if !template.isBuiltIn {
                template.sortOrder = Int64(100 + index)
            }
        }
        return save(reason: "Reordering templates")
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
