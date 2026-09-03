//
//  NoteRepository.swift
//  Maria's Notebook
//
//  Repository for CDNote entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
struct NoteRepository: SavingRepository {
    typealias Model = CDNote

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDNote by ID
    func fetchNote(id: UUID) -> CDNote? { fetch(id: id) }

    /// Fetch multiple Notes with optional filtering and sorting
    func fetchNotes(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "createdAt", ascending: false)]
    ) -> [CDNote] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        request.relationshipKeyPathsForPrefetching = ["studentLinks"]
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

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

    // MARK: - Delete

    /// Delete a CDNote by ID
    func deleteNote(id: UUID) throws {
        guard let note = fetchNote(id: id) else { return }
        note.deleteAssociatedImage()
        context.delete(note)
        try context.save()
    }
}
