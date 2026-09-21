//
//  MeetingTemplateRepository.swift
//  Cosmic Daybook
//
//  Repository for MeetingTemplate entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

struct MeetingTemplateRepository: SavingRepository {
    typealias Model = CDMeetingTemplate

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a MeetingTemplate by ID
    func fetchTemplate(id: UUID) -> CDMeetingTemplate? { fetch(id: id) }

    /// Fetch multiple MeetingTemplates with optional filtering and sorting
    func fetchTemplates(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "sortOrder", ascending: true)]
    ) -> [CDMeetingTemplate] {
        let request = CDFetchRequest(CDMeetingTemplate.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    /// Fetch only built-in templates
    func fetchBuiltInTemplates() -> [CDMeetingTemplate] {
        fetchTemplates(predicate: NSPredicate(format: "isBuiltIn == YES"))
    }

    /// Fetch only custom (user-created) templates
    func fetchCustomTemplates() -> [CDMeetingTemplate] {
        fetchTemplates(predicate: NSPredicate(format: "isBuiltIn == NO"))
    }

    // MARK: - Update

    /// Set a template as active (deactivates all others)
    @discardableResult
    func setActiveTemplate(id: UUID) -> Bool {
        let allTemplates = fetchTemplates()
        for template in allTemplates {
            template.isActive = false
        }

        guard let template = fetchTemplate(id: id) else { return false }
        template.isActive = true

        return save(reason: "Setting active meeting template")
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
        return save(reason: "Reordering meeting templates")
    }

    // MARK: - Delete

    /// Delete a MeetingTemplate by ID (only custom templates can be deleted)
    func deleteTemplate(id: UUID) throws {
        guard let template = fetchTemplate(id: id) else { return }
        guard !template.isBuiltIn else { return }

        if template.isActive {
            if let defaultTemplate = fetchBuiltInTemplates().first {
                defaultTemplate.isActive = true
            }
        }

        context.delete(template)
        try context.save()
    }
}
