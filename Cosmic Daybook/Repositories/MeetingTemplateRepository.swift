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

    // MARK: - Delete

    /// Deletes a custom MeetingTemplate by ID (built-in ones stay), handing
    /// the active mark to the first built-in one. Does not save: the caller
    /// saves and takes the change back if that fails (`SaveCoordinator.saveEdit`),
    /// since a delete that saved itself and failed stayed pending, to be
    /// saved by whatever saved next (bug hunt 2026-10-17, #42).
    func removeTemplate(id: UUID) {
        guard let template = fetchTemplate(id: id) else { return }
        guard !template.isBuiltIn else { return }

        if template.isActive {
            if let defaultTemplate = fetchBuiltInTemplates().first {
                defaultTemplate.isActive = true
            }
        }

        context.delete(template)
    }
}
