//
//  MeetingTemplateRepository.swift
//  Maria's Notebook
//
//  Repository for MeetingTemplate entity CRUD operations.
//  Follows the pattern established by NoteTemplateRepository.
//

import Foundation
import OSLog
import SwiftData

@MainActor
struct MeetingTemplateRepository: SavingRepository {
    typealias Model = MeetingTemplate

    private static let logger = Logger.database

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a MeetingTemplate by ID
    func fetchTemplate(id: UUID) -> MeetingTemplate? {
        var descriptor = FetchDescriptor<MeetingTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch multiple MeetingTemplates with optional filtering and sorting
    func fetchTemplates(
        predicate: Predicate<MeetingTemplate>? = nil,
        sortBy: [SortDescriptor<MeetingTemplate>] = [SortDescriptor(\.sortOrder)]
    ) -> [MeetingTemplate] {
        var descriptor = FetchDescriptor<MeetingTemplate>()
        if let predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return context.safeFetch(descriptor)
    }

    /// Fetch only built-in templates
    func fetchBuiltInTemplates() -> [MeetingTemplate] {
        let predicate = #Predicate<MeetingTemplate> { $0.isBuiltIn == true }
        return fetchTemplates(predicate: predicate)
    }

    /// Fetch only custom (user-created) templates
    func fetchCustomTemplates() -> [MeetingTemplate] {
        let predicate = #Predicate<MeetingTemplate> { $0.isBuiltIn == false }
        return fetchTemplates(predicate: predicate)
    }

    /// Fetch the currently active template
    func fetchActiveTemplate() -> MeetingTemplate? {
        let predicate = #Predicate<MeetingTemplate> { $0.isActive == true }
        return fetchTemplates(predicate: predicate).first
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
    ) -> MeetingTemplate {
        // Calculate sort order if not provided (after existing custom templates)
        let order: Int
        if let sortOrder {
            order = sortOrder
        } else {
            let customTemplates = fetchCustomTemplates()
            order = (customTemplates.map(\.sortOrder).max() ?? 99) + 1
        }

        let template = MeetingTemplate(
            name: name,
            reflectionPrompt: reflectionPrompt,
            focusPrompt: focusPrompt,
            requestsPrompt: requestsPrompt,
            guideNotesPrompt: guideNotesPrompt,
            sortOrder: order,
            isActive: false,
            isBuiltIn: false
        )
        context.insert(template)
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
        // Don't allow updating built-in templates
        guard !template.isBuiltIn else { return false }

        if let name {
            template.name = name
        }
        if let reflectionPrompt {
            template.reflectionPrompt = reflectionPrompt
        }
        if let focusPrompt {
            template.focusPrompt = focusPrompt
        }
        if let requestsPrompt {
            template.requestsPrompt = requestsPrompt
        }
        if let guideNotesPrompt {
            template.guideNotesPrompt = guideNotesPrompt
        }
        if let sortOrder {
            template.sortOrder = sortOrder
        }

        return true
    }

    /// Set a template as active (deactivates all others)
    @discardableResult
    func setActiveTemplate(id: UUID) -> Bool {
        // Deactivate all templates first
        let allTemplates = fetchTemplates()
        for template in allTemplates {
            template.isActive = false
        }

        // Activate the selected template
        guard let template = fetchTemplate(id: id) else { return false }
        template.isActive = true

        return save(reason: "Setting active meeting template")
    }

    /// Reorder custom templates by updating their sort orders
    @discardableResult
    func reorderTemplates(ids: [UUID]) -> Bool {
        // Start at 100 to keep custom templates after built-in
        for (index, id) in ids.enumerated() {
            guard let template = fetchTemplate(id: id) else { continue }
            // Only allow reordering custom templates
            if !template.isBuiltIn {
                template.sortOrder = 100 + index
            }
        }
        return save(reason: "Reordering meeting templates")
    }

    // MARK: - Delete

    /// Delete a MeetingTemplate by ID (only custom templates can be deleted)
    func deleteTemplate(id: UUID) throws {
        guard let template = fetchTemplate(id: id) else { return }
        // Don't allow deleting built-in templates
        guard !template.isBuiltIn else { return }

        // If deleting the active template, activate the default one
        if template.isActive {
            if let defaultTemplate = fetchBuiltInTemplates().first {
                defaultTemplate.isActive = true
            }
        }

        context.delete(template)
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error, privacy: .public)")
            throw error
        }
    }
}
