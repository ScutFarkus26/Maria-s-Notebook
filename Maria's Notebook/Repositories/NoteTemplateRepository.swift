//
//  NoteTemplateRepository.swift
//  Maria's Notebook
//
//  Repository for NoteTemplate entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
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
    func fetchTemplate(id: UUID) -> CDNoteTemplateEntity? {
        let request = CDFetchRequest(CDNoteTemplateEntity.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

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

    // MARK: - Create

    /// Create a new NoteTemplate
    @discardableResult
    func createTemplate(
        title: String,
        body: String,
        tags: [String] = [],
        sortOrder: Int? = nil
    ) -> CDNoteTemplateEntity {
        let order: Int
        if let sortOrder {
            order = sortOrder
        } else {
            let customTemplates = fetchCustomTemplates()
            order = (customTemplates.map { Int($0.sortOrder) }.max() ?? 99) + 1
        }

        let template = CDNoteTemplateEntity(context: context)
        template.title = title
        template.body = body
        template.tagsArray = tags
        template.sortOrder = Int64(order)
        template.isBuiltIn = false
        return template
    }

    // MARK: - Update

    /// Update an existing NoteTemplate's properties
    @discardableResult
    func updateTemplate(
        id: UUID,
        title: String? = nil,
        body: String? = nil,
        tags: [String]? = nil,
        sortOrder: Int? = nil
    ) -> Bool {
        guard let template = fetchTemplate(id: id) else { return false }
        guard !template.isBuiltIn else { return false }

        if let title { template.title = title }
        if let body { template.body = body }
        if let tags { template.tagsArray = tags }
        if let sortOrder { template.sortOrder = Int64(sortOrder) }

        return true
    }

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
