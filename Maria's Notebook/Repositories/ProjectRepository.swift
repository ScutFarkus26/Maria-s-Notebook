//
//  ProjectRepository.swift
//  Maria's Notebook
//
//  Repository for CDProject and CDProjectSession CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
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
    func fetchProject(id: UUID) -> CDProject? {
        let request = CDFetchRequest(CDProject.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

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

    /// Fetch active projects
    func fetchActiveProjects() -> [CDProject] {
        fetchProjects(predicate: NSPredicate(format: "isActive == YES"))
    }

    // MARK: - Create CDProject

    /// Create a new CDProject
    @discardableResult
    func createProject(
        title: String,
        bookTitle: String? = nil,
        memberStudentIDs: [UUID] = [],
        isActive: Bool = true
    ) -> CDProject {
        let project = CDProject(context: context)
        project.title = title
        project.bookTitle = bookTitle
        project.memberStudentUUIDs = memberStudentIDs
        project.isActive = isActive
        return project
    }

    // MARK: - Update CDProject

    /// Update an existing CDProject's properties
    @discardableResult
    func updateProject(
        id: UUID,
        title: String? = nil,
        bookTitle: String? = nil,
        memberStudentIDs: [UUID]? = nil,
        isActive: Bool? = nil
    ) -> Bool {
        guard let project = fetchProject(id: id) else { return false }

        if let title { project.title = title }
        if let bookTitle { project.bookTitle = bookTitle.isEmpty ? nil : bookTitle }
        if let memberStudentIDs { project.memberStudentUUIDs = memberStudentIDs }
        if let isActive { project.isActive = isActive }

        return true
    }

    // MARK: - Delete CDProject

    /// Delete a CDProject by ID
    func deleteProject(id: UUID) throws {
        guard let project = fetchProject(id: id) else { return }
        context.delete(project)
        try context.save()
    }

    // MARK: - Fetch Sessions

    /// Fetch a CDProjectSession by ID
    func fetchSession(id: UUID) -> CDProjectSession? {
        let request = CDFetchRequest(CDProjectSession.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    /// Fetch sessions for a project
    func fetchSessions(forProjectID projectID: UUID) -> [CDProjectSession] {
        let request = CDFetchRequest(CDProjectSession.self)
        request.predicate = NSPredicate(format: "projectID == %@", projectID.uuidString)
        request.sortDescriptors = [NSSortDescriptor(key: "meetingDate", ascending: true)]
        request.fetchBatchSize = 20
        return context.safeFetch(request)
    }

    // MARK: - Create Session

    /// Create a new CDProjectSession
    @discardableResult
    func createSession(
        projectID: UUID,
        meetingDate: Date = Date(),
        chapterOrPages: String? = nil,
        notes: String? = nil,
        agendaItems: [String] = []
    ) -> CDProjectSession {
        let session = CDProjectSession(context: context)
        session.projectIDUUID = projectID
        session.meetingDate = meetingDate
        session.chapterOrPages = chapterOrPages
        session.agendaItems = agendaItems
        if let notes {
            session.setLegacyNoteText(notes, in: context)
        }
        return session
    }

    // MARK: - Update Session

    /// Update an existing CDProjectSession's properties
    @discardableResult
    func updateSession(
        id: UUID,
        meetingDate: Date? = nil,
        chapterOrPages: String? = nil,
        notes: String? = nil,
        agendaItems: [String]? = nil
    ) -> Bool {
        guard let session = fetchSession(id: id) else { return false }

        if let meetingDate { session.meetingDate = meetingDate }
        if let chapterOrPages { session.chapterOrPages = chapterOrPages.isEmpty ? nil : chapterOrPages }
        if let notes { session.setLegacyNoteText(notes, in: context) }
        if let agendaItems { session.agendaItems = agendaItems }

        return true
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
