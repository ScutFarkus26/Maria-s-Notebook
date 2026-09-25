//
//  NoteRepository.swift
//  Cosmic Daybook
//
//  Repository for CDNote entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

struct NoteRepository: SavingRepository {
    typealias Model = CDNote

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDNote by ID
    func fetchNote(id: UUID) -> CDNote? { fetch(id: id) }

    // MARK: - Update

    /// Update an existing CDNote's properties
    @discardableResult
    func updateNote(
        id: UUID,
        body: String? = nil,
        tags: [String]? = nil,
        scope: NoteScope? = nil,
        isPinned: Bool? = nil,
        includeInReport: Bool? = nil,
        needsFollowUp: Bool? = nil
    ) -> Bool {
        guard let note = fetchNote(id: id) else { return false }

        if let body { note.body = body }
        if let tags { note.tagsArray = tags }
        if let scope {
            note.scope = scope
            note.syncStudentLinks(in: context)
        }
        if let isPinned { note.isPinned = isPinned }
        if let includeInReport { note.includeInReport = includeInReport }
        if let needsFollowUp { note.needsFollowUp = needsFollowUp }

        note.updatedAt = Date()
        return true
    }
}
