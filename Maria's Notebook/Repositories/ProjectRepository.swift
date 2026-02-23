//
//  ProjectRepository.swift
//  Maria's Notebook
//
//  Repository for Project, ProjectSession, and ProjectAssignmentTemplate CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import SwiftData

@MainActor
struct ProjectRepository: SavingRepository {
    typealias Model = Project

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch Projects

    /// Fetch a Project by ID
    func fetchProject(id: UUID) -> Project? {
        var descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch multiple Projects with optional filtering and sorting
    func fetchProjects(
        predicate: Predicate<Project>? = nil,
        sortBy: [SortDescriptor<Project>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) -> [Project] {
        var descriptor = FetchDescriptor<Project>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return context.safeFetch(descriptor)
    }

    /// Fetch active projects
    func fetchActiveProjects() -> [Project] {
        let predicate = #Predicate<Project> { $0.isActive }
        return fetchProjects(predicate: predicate)
    }

    // MARK: - Create Project

    /// Create a new Project
    @discardableResult
    func createProject(
        title: String,
        bookTitle: String? = nil,
        memberStudentIDs: [UUID] = [],
        isActive: Bool = true
    ) -> Project {
        let project = Project(
            title: title,
            bookTitle: bookTitle,
            memberStudentIDs: memberStudentIDs.map { $0.uuidString },
            isActive: isActive
        )
        context.insert(project)
        return project
    }

    // MARK: - Update Project

    /// Update an existing Project's properties
    @discardableResult
    func updateProject(
        id: UUID,
        title: String? = nil,
        bookTitle: String? = nil,
        memberStudentIDs: [UUID]? = nil,
        isActive: Bool? = nil
    ) -> Bool {
        guard let project = fetchProject(id: id) else { return false }

        if let title = title {
            project.title = title
        }
        if let bookTitle = bookTitle {
            project.bookTitle = bookTitle.isEmpty ? nil : bookTitle
        }
        if let memberStudentIDs = memberStudentIDs {
            project.memberStudentIDs = memberStudentIDs.map { $0.uuidString }
        }
        if let isActive = isActive {
            project.isActive = isActive
        }

        return true
    }

    // MARK: - Delete Project

    /// Delete a Project by ID
    func deleteProject(id: UUID) throws {
        guard let project = fetchProject(id: id) else { return }
        context.delete(project)
        do {
            try context.save()
        } catch {
            print("⚠️ [deleteProject] Failed to save context: \(error)")
            throw error
        }
    }

    // MARK: - Fetch Sessions

    /// Fetch a ProjectSession by ID
    func fetchSession(id: UUID) -> ProjectSession? {
        var descriptor = FetchDescriptor<ProjectSession>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch sessions for a project
    func fetchSessions(forProjectID projectID: UUID) -> [ProjectSession] {
        let projectIDString = projectID.uuidString
        let descriptor = FetchDescriptor<ProjectSession>(
            predicate: #Predicate { $0.projectID == projectIDString },
            sortBy: [SortDescriptor(\.meetingDate)]
        )
        return context.safeFetch(descriptor)
    }

    // MARK: - Create Session

    /// Create a new ProjectSession
    @discardableResult
    func createSession(
        projectID: UUID,
        meetingDate: Date = Date(),
        chapterOrPages: String? = nil,
        notes: String? = nil,
        agendaItems: [String] = []
    ) -> ProjectSession {
        let session = ProjectSession(
            projectID: projectID,
            meetingDate: meetingDate,
            chapterOrPages: chapterOrPages,
            notes: nil
        )
        session.agendaItems = agendaItems
        context.insert(session)
        if let notes {
            _ = session.setLegacyNoteText(notes, in: context)
        }
        return session
    }

    // MARK: - Update Session

    /// Update an existing ProjectSession's properties
    @discardableResult
    func updateSession(
        id: UUID,
        meetingDate: Date? = nil,
        chapterOrPages: String? = nil,
        notes: String? = nil,
        agendaItems: [String]? = nil
    ) -> Bool {
        guard let session = fetchSession(id: id) else { return false }

        if let meetingDate = meetingDate {
            session.meetingDate = meetingDate
        }
        if let chapterOrPages = chapterOrPages {
            session.chapterOrPages = chapterOrPages.isEmpty ? nil : chapterOrPages
        }
        if let notes {
            _ = session.setLegacyNoteText(notes, in: context)
        }
        if let agendaItems = agendaItems {
            session.agendaItems = agendaItems
        }

        return true
    }

    // MARK: - Delete Session

    /// Delete a ProjectSession by ID
    func deleteSession(id: UUID) throws {
        guard let session = fetchSession(id: id) else { return }
        context.delete(session)
        do {
            try context.save()
        } catch {
            print("⚠️ [deleteSession] Failed to save context: \(error)")
            throw error
        }
    }

    // MARK: - Fetch Templates

    /// Fetch a ProjectAssignmentTemplate by ID
    func fetchTemplate(id: UUID) -> ProjectAssignmentTemplate? {
        var descriptor = FetchDescriptor<ProjectAssignmentTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return context.safeFetchFirst(descriptor)
    }

    /// Fetch templates for a project
    func fetchTemplates(forProjectID projectID: UUID) -> [ProjectAssignmentTemplate] {
        let projectIDString = projectID.uuidString
        let descriptor = FetchDescriptor<ProjectAssignmentTemplate>(
            predicate: #Predicate { $0.projectID == projectIDString },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return context.safeFetch(descriptor)
    }

    // MARK: - Create Template

    /// Create a new ProjectAssignmentTemplate
    @discardableResult
    func createTemplate(
        projectID: UUID,
        title: String,
        instructions: String = "",
        isShared: Bool = true,
        defaultLinkedLessonID: UUID? = nil
    ) -> ProjectAssignmentTemplate {
        let template = ProjectAssignmentTemplate(
            projectID: projectID,
            title: title,
            instructions: instructions,
            isShared: isShared,
            defaultLinkedLessonID: defaultLinkedLessonID?.uuidString
        )
        context.insert(template)
        return template
    }

    // MARK: - Delete Template

    /// Delete a ProjectAssignmentTemplate by ID
    func deleteTemplate(id: UUID) throws {
        guard let template = fetchTemplate(id: id) else { return }
        context.delete(template)
        do {
            try context.save()
        } catch {
            print("⚠️ [deleteTemplate] Failed to save context: \(error)")
            throw error
        }
    }
}
