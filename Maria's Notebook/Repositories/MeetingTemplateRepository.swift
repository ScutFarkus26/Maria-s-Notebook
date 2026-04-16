//
//  MeetingTemplateRepository.swift
//  Maria's Notebook
//
//  Repository for MeetingTemplate entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
struct MeetingTemplateRepository: SavingRepository {
    typealias Model = CDMeetingTemplateEntity

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a MeetingTemplate by ID
    func fetchTemplate(id: UUID) -> CDMeetingTemplateEntity? {
        let request = CDFetchRequest(CDMeetingTemplateEntity.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    /// Fetch multiple MeetingTemplates with optional filtering and sorting
    func fetchTemplates(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "sortOrder", ascending: true)]
    ) -> [CDMeetingTemplateEntity] {
        let request = CDFetchRequest(CDMeetingTemplateEntity.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    /// Fetch only built-in templates
    func fetchBuiltInTemplates() -> [CDMeetingTemplateEntity] {
        fetchTemplates(predicate: NSPredicate(format: "isBuiltIn == YES"))
    }

    /// Fetch only custom (user-created) templates
    func fetchCustomTemplates() -> [CDMeetingTemplateEntity] {
        fetchTemplates(predicate: NSPredicate(format: "isBuiltIn == NO"))
    }

    /// Fetch the currently active template
    func fetchActiveTemplate() -> CDMeetingTemplateEntity? {
        fetchTemplates(predicate: NSPredicate(format: "isActive == YES")).first
    }

    // MARK: - Create

    /// Create a new MeetingTemplate
    @discardableResult
    func createTemplate(
        name: String,
        reflectionPrompt: String,
        focusPrompt: String,
        requestsPrompt: String,
        guideNotesPrompt: String,
        sortOrder: Int? = nil
    ) -> CDMeetingTemplateEntity {
        let order: Int
        if let sortOrder {
            order = sortOrder
        } else {
            let customTemplates = fetchCustomTemplates()
            order = (customTemplates.map { Int($0.sortOrder) }.max() ?? 99) + 1
        }

        let template = CDMeetingTemplateEntity(context: context)
        template.name = name
        template.reflectionPrompt = reflectionPrompt
        template.focusPrompt = focusPrompt
        template.requestsPrompt = requestsPrompt
        template.guideNotesPrompt = guideNotesPrompt
        template.sortOrder = Int64(order)
        template.isActive = false
        template.isBuiltIn = false
        return template
    }

    // MARK: - Update

    /// Update an existing MeetingTemplate's properties
    @discardableResult
    func updateTemplate(
        id: UUID,
        name: String? = nil,
        reflectionPrompt: String? = nil,
        focusPrompt: String? = nil,
        requestsPrompt: String? = nil,
        guideNotesPrompt: String? = nil,
        sortOrder: Int? = nil
    ) -> Bool {
        guard let template = fetchTemplate(id: id) else { return false }
        guard !template.isBuiltIn else { return false }

        if let name { template.name = name }
        if let reflectionPrompt { template.reflectionPrompt = reflectionPrompt }
        if let focusPrompt { template.focusPrompt = focusPrompt }
        if let requestsPrompt { template.requestsPrompt = requestsPrompt }
        if let guideNotesPrompt { template.guideNotesPrompt = guideNotesPrompt }
        if let sortOrder { template.sortOrder = Int64(sortOrder) }

        return true
    }

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
