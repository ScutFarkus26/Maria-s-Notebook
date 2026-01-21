#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Project Fetch Tests

@Suite("ProjectRepository Project Fetch Tests", .serialized)
@MainActor
struct ProjectRepositoryProjectFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Project.self,
            ProjectSession.self,
            ProjectAssignmentTemplate.self,
            ProjectRole.self,
            Note.self,
        ])
    }

    @Test("fetchProject returns project by ID")
    func fetchProjectReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(title: "Test Project")
        context.insert(project)
        try context.save()

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchProject(id: project.id)

        #expect(fetched != nil)
        #expect(fetched?.id == project.id)
        #expect(fetched?.title == "Test Project")
    }

    @Test("fetchProject returns nil for missing ID")
    func fetchProjectReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchProject(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchProjects returns all when no predicate")
    func fetchProjectsReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project1 = Project(title: "Project 1")
        let project2 = Project(title: "Project 2")
        let project3 = Project(title: "Project 3")
        context.insert(project1)
        context.insert(project2)
        context.insert(project3)
        try context.save()

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchProjects()

        #expect(fetched.count == 3)
    }

    @Test("fetchProjects sorts by createdAt descending by default")
    func fetchProjectsSortsByCreatedAtDesc() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let project1 = Project(title: "Old Project")
        project1.createdAt = oldDate
        let project2 = Project(title: "New Project")
        project2.createdAt = newDate
        context.insert(project1)
        context.insert(project2)
        try context.save()

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchProjects()

        #expect(fetched[0].title == "New Project")
        #expect(fetched[1].title == "Old Project")
    }

    @Test("fetchActiveProjects returns active only")
    func fetchActiveProjectsReturnsActiveOnly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project1 = Project(title: "Active Project", isActive: true)
        let project2 = Project(title: "Inactive Project", isActive: false)
        context.insert(project1)
        context.insert(project2)
        try context.save()

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchActiveProjects()

        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Active Project")
    }

    @Test("fetchProjects handles empty database")
    func fetchProjectsHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchProjects()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Project Create Tests

@Suite("ProjectRepository Project Create Tests", .serialized)
@MainActor
struct ProjectRepositoryProjectCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Project.self,
            ProjectSession.self,
            ProjectAssignmentTemplate.self,
            ProjectRole.self,
            Note.self,
        ])
    }

    @Test("createProject creates project with required fields")
    func createProjectCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ProjectRepository(context: context)
        let project = repository.createProject(title: "Test Project")

        #expect(project.title == "Test Project")
        #expect(project.isActive == true) // Default
    }

    @Test("createProject sets optional fields when provided")
    func createProjectSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()

        let repository = ProjectRepository(context: context)
        let project = repository.createProject(
            title: "Book Club",
            bookTitle: "Charlotte's Web",
            memberStudentIDs: [studentID],
            isActive: false
        )

        #expect(project.title == "Book Club")
        #expect(project.bookTitle == "Charlotte's Web")
        #expect(project.memberStudentIDs == [studentID.uuidString])
        #expect(project.isActive == false)
    }

    @Test("createProject persists to context")
    func createProjectPersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ProjectRepository(context: context)
        let project = repository.createProject(title: "Test Project")

        let fetched = repository.fetchProject(id: project.id)

        #expect(fetched != nil)
        #expect(fetched?.id == project.id)
    }
}

// MARK: - Project Update Tests

@Suite("ProjectRepository Project Update Tests", .serialized)
@MainActor
struct ProjectRepositoryProjectUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Project.self,
            ProjectSession.self,
            ProjectAssignmentTemplate.self,
            ProjectRole.self,
            Note.self,
        ])
    }

    @Test("updateProject updates title")
    func updateProjectUpdatesTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(title: "Original Title")
        context.insert(project)
        try context.save()

        let repository = ProjectRepository(context: context)
        let result = repository.updateProject(id: project.id, title: "Updated Title")

        #expect(result == true)
        #expect(project.title == "Updated Title")
    }

    @Test("updateProject updates bookTitle")
    func updateProjectUpdatesBookTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(title: "Book Club")
        context.insert(project)
        try context.save()

        let repository = ProjectRepository(context: context)
        let result = repository.updateProject(id: project.id, bookTitle: "New Book")

        #expect(result == true)
        #expect(project.bookTitle == "New Book")
    }

    @Test("updateProject clears bookTitle when empty string")
    func updateProjectClearsBookTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(title: "Book Club", bookTitle: "Old Book")
        context.insert(project)
        try context.save()

        let repository = ProjectRepository(context: context)
        let result = repository.updateProject(id: project.id, bookTitle: "")

        #expect(result == true)
        #expect(project.bookTitle == nil)
    }

    @Test("updateProject updates memberStudentIDs")
    func updateProjectUpdatesMemberStudentIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(title: "Group Project")
        context.insert(project)
        try context.save()

        let studentID1 = UUID()
        let studentID2 = UUID()

        let repository = ProjectRepository(context: context)
        let result = repository.updateProject(id: project.id, memberStudentIDs: [studentID1, studentID2])

        #expect(result == true)
        #expect(project.memberStudentIDs.count == 2)
    }

    @Test("updateProject updates isActive")
    func updateProjectUpdatesIsActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(title: "Test Project", isActive: true)
        context.insert(project)
        try context.save()

        let repository = ProjectRepository(context: context)
        let result = repository.updateProject(id: project.id, isActive: false)

        #expect(result == true)
        #expect(project.isActive == false)
    }

    @Test("updateProject returns false for missing ID")
    func updateProjectReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ProjectRepository(context: context)
        let result = repository.updateProject(id: UUID(), title: "New Title")

        #expect(result == false)
    }
}

// MARK: - Project Delete Tests

@Suite("ProjectRepository Project Delete Tests", .serialized)
@MainActor
struct ProjectRepositoryProjectDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Project.self,
            ProjectSession.self,
            ProjectAssignmentTemplate.self,
            ProjectRole.self,
            Note.self,
        ])
    }

    @Test("deleteProject removes project from context")
    func deleteProjectRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let project = Project(title: "Test Project")
        context.insert(project)
        try context.save()

        let projectID = project.id

        let repository = ProjectRepository(context: context)
        try repository.deleteProject(id: projectID)

        let fetched = repository.fetchProject(id: projectID)
        #expect(fetched == nil)
    }

    @Test("deleteProject does nothing for missing ID")
    func deleteProjectDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ProjectRepository(context: context)
        try repository.deleteProject(id: UUID())

        // Should not throw
    }
}

// MARK: - Session Fetch Tests

@Suite("ProjectRepository Session Fetch Tests", .serialized)
@MainActor
struct ProjectRepositorySessionFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Project.self,
            ProjectSession.self,
            ProjectAssignmentTemplate.self,
            ProjectRole.self,
            Note.self,
        ])
    }

    @Test("fetchSession returns session by ID")
    func fetchSessionReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()
        let session = ProjectSession(projectID: projectID)
        context.insert(session)
        try context.save()

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchSession(id: session.id)

        #expect(fetched != nil)
        #expect(fetched?.id == session.id)
    }

    @Test("fetchSession returns nil for missing ID")
    func fetchSessionReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchSession(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchSessions forProjectID filters correctly")
    func fetchSessionsForProjectIDFilters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID1 = UUID()
        let projectID2 = UUID()

        let session1 = ProjectSession(projectID: projectID1)
        let session2 = ProjectSession(projectID: projectID1)
        let session3 = ProjectSession(projectID: projectID2)
        context.insert(session1)
        context.insert(session2)
        context.insert(session3)
        try context.save()

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchSessions(forProjectID: projectID1)

        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.projectID == projectID1.uuidString })
    }
}

// MARK: - Session Create Tests

@Suite("ProjectRepository Session Create Tests", .serialized)
@MainActor
struct ProjectRepositorySessionCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Project.self,
            ProjectSession.self,
            ProjectAssignmentTemplate.self,
            ProjectRole.self,
            Note.self,
        ])
    }

    @Test("createSession creates session with required fields")
    func createSessionCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()

        let repository = ProjectRepository(context: context)
        let session = repository.createSession(projectID: projectID)

        #expect(session.projectID == projectID.uuidString)
    }

    @Test("createSession sets optional fields when provided")
    func createSessionSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()
        let meetingDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        let repository = ProjectRepository(context: context)
        let session = repository.createSession(
            projectID: projectID,
            meetingDate: meetingDate,
            chapterOrPages: "Chapter 5",
            notes: "Discussed character development",
            agendaItems: ["Review chapter", "Discuss themes"]
        )

        #expect(session.meetingDate == meetingDate)
        #expect(session.chapterOrPages == "Chapter 5")
        #expect(session.notes == "Discussed character development")
        #expect(session.agendaItems == ["Review chapter", "Discuss themes"])
    }

    @Test("createSession persists to context")
    func createSessionPersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()

        let repository = ProjectRepository(context: context)
        let session = repository.createSession(projectID: projectID)

        let fetched = repository.fetchSession(id: session.id)

        #expect(fetched != nil)
        #expect(fetched?.id == session.id)
    }
}

// MARK: - Session Update Tests

@Suite("ProjectRepository Session Update Tests", .serialized)
@MainActor
struct ProjectRepositorySessionUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Project.self,
            ProjectSession.self,
            ProjectAssignmentTemplate.self,
            ProjectRole.self,
            Note.self,
        ])
    }

    @Test("updateSession updates meetingDate")
    func updateSessionUpdatesMeetingDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()
        let session = ProjectSession(projectID: projectID)
        context.insert(session)
        try context.save()

        let newDate = TestCalendar.date(year: 2025, month: 3, day: 20)

        let repository = ProjectRepository(context: context)
        let result = repository.updateSession(id: session.id, meetingDate: newDate)

        #expect(result == true)
        #expect(session.meetingDate == newDate)
    }

    @Test("updateSession updates chapterOrPages")
    func updateSessionUpdatesChapterOrPages() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()
        let session = ProjectSession(projectID: projectID)
        context.insert(session)
        try context.save()

        let repository = ProjectRepository(context: context)
        let result = repository.updateSession(id: session.id, chapterOrPages: "Pages 50-75")

        #expect(result == true)
        #expect(session.chapterOrPages == "Pages 50-75")
    }

    @Test("updateSession clears chapterOrPages when empty")
    func updateSessionClearsChapterOrPages() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()
        let session = ProjectSession(projectID: projectID, chapterOrPages: "Chapter 1")
        context.insert(session)
        try context.save()

        let repository = ProjectRepository(context: context)
        let result = repository.updateSession(id: session.id, chapterOrPages: "")

        #expect(result == true)
        #expect(session.chapterOrPages == nil)
    }

    @Test("updateSession returns false for missing ID")
    func updateSessionReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ProjectRepository(context: context)
        let result = repository.updateSession(id: UUID(), notes: "Test")

        #expect(result == false)
    }
}

// MARK: - Session Delete Tests

@Suite("ProjectRepository Session Delete Tests", .serialized)
@MainActor
struct ProjectRepositorySessionDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Project.self,
            ProjectSession.self,
            ProjectAssignmentTemplate.self,
            ProjectRole.self,
            Note.self,
        ])
    }

    @Test("deleteSession removes session from context")
    func deleteSessionRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()
        let session = ProjectSession(projectID: projectID)
        context.insert(session)
        try context.save()

        let sessionID = session.id

        let repository = ProjectRepository(context: context)
        try repository.deleteSession(id: sessionID)

        let fetched = repository.fetchSession(id: sessionID)
        #expect(fetched == nil)
    }

    @Test("deleteSession does nothing for missing ID")
    func deleteSessionDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ProjectRepository(context: context)
        try repository.deleteSession(id: UUID())

        // Should not throw
    }
}

// MARK: - Template Tests

@Suite("ProjectRepository Template Tests", .serialized)
@MainActor
struct ProjectRepositoryTemplateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Project.self,
            ProjectSession.self,
            ProjectAssignmentTemplate.self,
            ProjectRole.self,
            Note.self,
        ])
    }

    @Test("fetchTemplate returns template by ID")
    func fetchTemplateReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()
        let template = ProjectAssignmentTemplate(projectID: projectID, title: "Book Report")
        context.insert(template)
        try context.save()

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchTemplate(id: template.id)

        #expect(fetched != nil)
        #expect(fetched?.title == "Book Report")
    }

    @Test("fetchTemplates forProjectID filters correctly")
    func fetchTemplatesForProjectIDFilters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID1 = UUID()
        let projectID2 = UUID()

        let template1 = ProjectAssignmentTemplate(projectID: projectID1, title: "Template 1")
        let template2 = ProjectAssignmentTemplate(projectID: projectID2, title: "Template 2")
        context.insert(template1)
        context.insert(template2)
        try context.save()

        let repository = ProjectRepository(context: context)
        let fetched = repository.fetchTemplates(forProjectID: projectID1)

        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Template 1")
    }

    @Test("createTemplate creates template with required fields")
    func createTemplateCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()

        let repository = ProjectRepository(context: context)
        let template = repository.createTemplate(
            projectID: projectID,
            title: "Discussion Guide"
        )

        #expect(template.projectID == projectID.uuidString)
        #expect(template.title == "Discussion Guide")
        #expect(template.isShared == true) // Default
    }

    @Test("createTemplate sets optional fields")
    func createTemplateSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()
        let lessonID = UUID()

        let repository = ProjectRepository(context: context)
        let template = repository.createTemplate(
            projectID: projectID,
            title: "Book Report",
            instructions: "Write a 2-page summary",
            isShared: false,
            defaultLinkedLessonID: lessonID
        )

        #expect(template.instructions == "Write a 2-page summary")
        #expect(template.isShared == false)
        #expect(template.defaultLinkedLessonID == lessonID.uuidString)
    }

    @Test("deleteTemplate removes template from context")
    func deleteTemplateRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let projectID = UUID()
        let template = ProjectAssignmentTemplate(projectID: projectID, title: "Template")
        context.insert(template)
        try context.save()

        let templateID = template.id

        let repository = ProjectRepository(context: context)
        try repository.deleteTemplate(id: templateID)

        let fetched = repository.fetchTemplate(id: templateID)
        #expect(fetched == nil)
    }
}

#endif
