//
//  ProjectRepository.swift
//  Maria's Notebook
//
//  Repository for CDProject and CDProjectSession CRUD operations.
//

import Foundation
import OSLog
import CoreData

struct ProjectRepository: SavingRepository {
    typealias Model = CDProject

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch Projects

    /// Fetch a CDProject by ID
    func fetchProject(id: UUID) -> CDProject? { fetch(id: id) }

    /// Fetch multiple Projects with optional filtering and sorting
    func fetchProjects(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "createdAt", ascending: false)]
    ) -> [CDProject] {
        let request = CDFetchRequest(CDProject.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    // MARK: - Fetch Sessions

    /// Fetch a CDProjectSession by ID
    func fetchSession(id: UUID) -> CDProjectSession? {
        context.object(CDProjectSession.self, id: id)
    }

    // MARK: - Delete Session

    /// Delete a CDProjectSession by ID
    func deleteSession(id: UUID) throws {
        guard let session = fetchSession(id: id) else { return }
        context.delete(session)
        try context.save()
    }

    // Template methods removed — CDProjectAssignmentTemplate deprecated.
}
