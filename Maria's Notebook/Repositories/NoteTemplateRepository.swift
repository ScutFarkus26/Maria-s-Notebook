//
//  NoteTemplateRepository.swift
//  Maria's Notebook
//
//  Repository for NoteTemplate entity CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import OSLog
import SwiftData

@MainActor
struct NoteTemplateRepository: SavingRepository {
    typealias Model = NoteTemplate

    private static let logger = Logger.database

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a NoteTemplate by ID
    func fetchTemplate(id: UUID) -> NoteTemplate? {
        var descriptor = FetchDescriptor<NoteTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch multiple NoteTemplates with optional filtering and sorting
    /// - Parameters:
    ///   - predicate: Optional predicate to filter templates. If nil, fetches all.
    ///   - sortBy: Optional sort descriptors. Defaults to sorting by sortOrder.
    /// - Returns: Array of NoteTemplate entities matching the criteria
    func fetchTemplates(
        predicate: Predicate<NoteTemplate>? = nil,
        sortBy: [SortDescriptor<NoteTemplate>] = [SortDescriptor(\.sortOrder)]
    ) -> [NoteTemplate] {
        var descriptor = FetchDescriptor<NoteTemplate>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return context.safeFetch(descriptor)
    }

    /// Fetch only built-in templates
    func fetchBuiltInTemplates() -> [NoteTemplate] {
        let predicate = #Predicate<NoteTemplate> { $0.isBuiltIn == true }
        return fetchTemplates(predicate: predicate)
    }

    /// Fetch only custom (user-created) templates
    func fetchCustomTemplates() -> [NoteTemplate] {
        let predicate = #Predicate<NoteTemplate> { $0.isBuiltIn == false }
        return fetchTemplates(predicate: predicate)
    }

    // MARK: - Create

    /// Create a new NoteTemplate
    /// - Parameters:
    ///   - title: Short title for the template
    ///   - body: Full template text
    ///   - category: The category to auto-select. Defaults to .general
    ///   - sortOrder: Display order. Defaults to after existing custom templates.
    /// - Returns: The created NoteTemplate entity
    @discardableResult
    func createTemplate(
        title: String,
        body: String,
        tags: [String] = [],
        sortOrder: Int? = nil
    ) -> NoteTemplate {
        // Calculate sort order if not provided (after existing custom templates)
        let order: Int
        if let sortOrder = sortOrder {
            order = sortOrder
        } else {
            let customTemplates = fetchCustomTemplates()
            order = (customTemplates.map { $0.sortOrder }.max() ?? 99) + 1
        }

        let template = NoteTemplate(
            title: title,
            body: body,
            tags: tags,
            sortOrder: order,
            isBuiltIn: false
        )
        context.insert(template)
        return template
    }

    // MARK: - Update

    /// Update an existing NoteTemplate's properties
    /// - Parameters:
    ///   - id: The UUID of the template to update
    ///   - title: New title (optional)
    ///   - body: New body (optional)
    ///   - category: New category (optional)
    ///   - sortOrder: New sort order (optional)
    /// - Returns: true if update succeeded, false if template not found or is built-in
    @discardableResult
    func updateTemplate(
        id: UUID,
        title: String? = nil,
        body: String? = nil,
        tags: [String]? = nil,
        sortOrder: Int? = nil
    ) -> Bool {
        guard let template = fetchTemplate(id: id) else { return false }
        // Don't allow updating built-in templates
        guard !template.isBuiltIn else { return false }

        if let title = title {
            template.title = title
        }
        if let body = body {
            template.body = body
        }
        if let tags = tags {
            template.tags = tags
        }
        if let sortOrder = sortOrder {
            template.sortOrder = sortOrder
        }

        return true
    }

    /// Reorder custom templates by updating their sort orders
    /// - Parameter ids: Array of template IDs in desired order
    /// - Returns: true if reorder succeeded
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
        return save(reason: "Reordering templates")
    }

    // MARK: - Delete

    /// Delete a NoteTemplate by ID (only custom templates can be deleted)
    func deleteTemplate(id: UUID) throws {
        guard let template = fetchTemplate(id: id) else { return }
        // Don't allow deleting built-in templates
        guard !template.isBuiltIn else { return }
        context.delete(template)
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error, privacy: .public)")
            throw error
        }
    }
}
