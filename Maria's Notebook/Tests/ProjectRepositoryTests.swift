#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Test Context Setup

@MainActor
private struct RepositoryTestContext {
    let container: ModelContainer
    let context: ModelContext
    let repository: ProjectRepository

    static func make() throws -> RepositoryTestContext {
        let container = try makeTestContainer(for: [
            Student.self, Project.self, ProjectSession.self,
            ProjectAssignmentTemplate.self, ProjectRole.self, Note.self,
        ])
        let context = ModelContext(container)
        let repository = ProjectRepository(context: context)
        return RepositoryTestContext(container: container, context: context, repository: repository)
    }
}

// MARK: - Project Fetch Tests

@Suite("ProjectRepository Project Fetch Tests", .serialized)
@MainActor
struct ProjectRepositoryProjectFetchTests {

    @Test("fetchProject returns project by ID")
    func fetchProjectReturnsById() throws {
        let tc = try RepositoryTestContext.make()
        let project = Project(title: "Test Project")
        tc.context.insert(project)
        try tc.context.save()

        let fetched = tc.repository.fetchProject(id: project.id)

        #expect(fetched != nil)
        #expect(fetched?.id == project.id)
        #expect(fetched?.title == "Test Project")
    }

    @Test("fetchProject returns nil for missing ID")
    func fetchProjectReturnsNilForMissingId() throws {
        let tc = try RepositoryTestContext.make()
        let fetched = tc.repository.fetchProject(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchProjects returns all when no predicate")
    func fetchProjectsReturnsAllWhenNoPredicate() throws {
        let tc = try RepositoryTestContext.make()
        [Project(title: "Project 1"), Project(title: "Project 2"), Project(title: "Project 3")]
            .forEach { tc.context.insert($0) }
        try tc.context.save()

        let fetched = tc.repository.fetchProjects()

        #expect(fetched.count == 3)
    }

    @Test("fetchProjects sorts by createdAt descending by default")
    func fetchProjectsSortsByCreatedAtDesc() throws {
        let tc = try RepositoryTestContext.make()
        let oldProject = Project(title: "Old Project")
        oldProject.createdAt = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newProject = Project(title: "New Project")
        newProject.createdAt = TestCalendar.date(year: 2025, month: 6, day: 15)
        tc.context.insert(oldProject)
        tc.context.insert(newProject)
        try tc.context.save()

        let fetched = tc.repository.fetchProjects()

        #expect(fetched[0].title == "New Project")
        #expect(fetched[1].title == "Old Project")
    }

    @Test("fetchActiveProjects returns active only")
    func fetchActiveProjectsReturnsActiveOnly() throws {
        let tc = try RepositoryTestContext.make()
        tc.context.insert(Project(title: "Active Project", isActive: true))
        tc.context.insert(Project(title: "Inactive Project", isActive: false))
        try tc.context.save()

        let fetched = tc.repository.fetchActiveProjects()

        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Active Project")
    }

    @Test("fetchProjects handles empty database")
    func fetchProjectsHandlesEmptyDatabase() throws {
        let tc = try RepositoryTestContext.make()
        let fetched = tc.repository.fetchProjects()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Project Create Tests

@Suite("ProjectRepository Project Create Tests", .serialized)
@MainActor
struct ProjectRepositoryProjectCreateTests {

    @Test("createProject creates project with required fields")
    func createProjectCreatesWithRequiredFields() throws {
        let tc = try RepositoryTestContext.make()
        let project = tc.repository.createProject(title: "Test Project")

        #expect(project.title == "Test Project")
        #expect(project.isActive == true)
    }

    @Test("createProject sets optional fields when provided")
    func createProjectSetsOptionalFields() throws {
        let tc = try RepositoryTestContext.make()
        let studentID = UUID()

        let project = tc.repository.createProject(
            title: "Book Club", bookTitle: "Charlotte's Web",
            memberStudentIDs: [studentID], isActive: false
        )

        #expect(project.title == "Book Club")
        #expect(project.bookTitle == "Charlotte's Web")
        #expect(project.memberStudentIDs == [studentID.uuidString])
        #expect(project.isActive == false)
    }

    @Test("createProject persists to context")
    func createProjectPersistsToContext() throws {
        let tc = try RepositoryTestContext.make()
        let project = tc.repository.createProject(title: "Test Project")
        let fetched = tc.repository.fetchProject(id: project.id)

        #expect(fetched != nil)
        #expect(fetched?.id == project.id)
    }
}

// MARK: - Project Update Tests

@Suite("ProjectRepository Project Update Tests", .serialized)
@MainActor
struct ProjectRepositoryProjectUpdateTests {

    @Test("updateProject updates title")
    func updateProjectUpdatesTitle() throws {
        let tc = try RepositoryTestContext.make()
        let project = Project(title: "Original Title")
        tc.context.insert(project)
        try tc.context.save()

        let result = tc.repository.updateProject(id: project.id, title: "Updated Title")

        #expect(result == true)
        #expect(project.title == "Updated Title")
    }

    @Test("updateProject updates bookTitle")
    func updateProjectUpdatesBookTitle() throws {
        let tc = try RepositoryTestContext.make()
        let project = Project(title: "Book Club")
        tc.context.insert(project)
        try tc.context.save()

        let result = tc.repository.updateProject(id: project.id, bookTitle: "New Book")

        #expect(result == true)
        #expect(project.bookTitle == "New Book")
    }

    @Test("updateProject clears bookTitle when empty string")
    func updateProjectClearsBookTitle() throws {
        let tc = try RepositoryTestContext.make()
        let project = Project(title: "Book Club", bookTitle: "Old Book")
        tc.context.insert(project)
        try tc.context.save()

        let result = tc.repository.updateProject(id: project.id, bookTitle: "")

        #expect(result == true)
        #expect(project.bookTitle == nil)
    }

    @Test("updateProject updates memberStudentIDs")
    func updateProjectUpdatesMemberStudentIDs() throws {
        let tc = try RepositoryTestContext.make()
        let project = Project(title: "Group Project")
        tc.context.insert(project)
        try tc.context.save()

        let result = tc.repository.updateProject(id: project.id, memberStudentIDs: [UUID(), UUID()])

        #expect(result == true)
        #expect(project.memberStudentIDs.count == 2)
    }

    @Test("updateProject updates isActive")
    func updateProjectUpdatesIsActive() throws {
        let tc = try RepositoryTestContext.make()
        let project = Project(title: "Test Project", isActive: true)
        tc.context.insert(project)
        try tc.context.save()

        let result = tc.repository.updateProject(id: project.id, isActive: false)

        #expect(result == true)
        #expect(project.isActive == false)
    }

    @Test("updateProject returns false for missing ID")
    func updateProjectReturnsFalseForMissingId() throws {
        let tc = try RepositoryTestContext.make()
        let result = tc.repository.updateProject(id: UUID(), title: "New Title")

        #expect(result == false)
    }
}

// MARK: - Project Delete Tests

@Suite("ProjectRepository Project Delete Tests", .serialized)
@MainActor
struct ProjectRepositoryProjectDeleteTests {

    @Test("deleteProject removes project from context")
    func deleteProjectRemovesFromContext() throws {
        let tc = try RepositoryTestContext.make()
        let project = Project(title: "Test Project")
        tc.context.insert(project)
        try tc.context.save()
        let projectID = project.id

        try tc.repository.deleteProject(id: projectID)

        #expect(tc.repository.fetchProject(id: projectID) == nil)
    }

    @Test("deleteProject does nothing for missing ID")
    func deleteProjectDoesNothingForMissingId() throws {
        let tc = try RepositoryTestContext.make()
        try tc.repository.deleteProject(id: UUID())
        // Should not throw
    }
}

// MARK: - Session Fetch Tests

@Suite("ProjectRepository Session Fetch Tests", .serialized)
@MainActor
struct ProjectRepositorySessionFetchTests {

    @Test("fetchSession returns session by ID")
    func fetchSessionReturnsById() throws {
        let tc = try RepositoryTestContext.make()
        let session = ProjectSession(projectID: UUID())
        tc.context.insert(session)
        try tc.context.save()

        let fetched = tc.repository.fetchSession(id: session.id)

        #expect(fetched != nil)
        #expect(fetched?.id == session.id)
    }

    @Test("fetchSession returns nil for missing ID")
    func fetchSessionReturnsNilForMissingId() throws {
        let tc = try RepositoryTestContext.make()
        let fetched = tc.repository.fetchSession(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchSessions forProjectID filters correctly")
    func fetchSessionsForProjectIDFilters() throws {
        let tc = try RepositoryTestContext.make()
        let projectID1 = UUID()
        let projectID2 = UUID()

        [ProjectSession(projectID: projectID1), ProjectSession(projectID: projectID1), ProjectSession(projectID: projectID2)]
            .forEach { tc.context.insert($0) }
        try tc.context.save()

        let fetched = tc.repository.fetchSessions(forProjectID: projectID1)

        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.projectID == projectID1.uuidString })
    }
}

// MARK: - Session Create Tests

@Suite("ProjectRepository Session Create Tests", .serialized)
@MainActor
struct ProjectRepositorySessionCreateTests {

    @Test("createSession creates session with required fields")
    func createSessionCreatesWithRequiredFields() throws {
        let tc = try RepositoryTestContext.make()
        let projectID = UUID()
        let session = tc.repository.createSession(projectID: projectID)

        #expect(session.projectID == projectID.uuidString)
    }

    @Test("createSession sets optional fields when provided")
    func createSessionSetsOptionalFields() throws {
        let tc = try RepositoryTestContext.make()
        let projectID = UUID()
        let meetingDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        let session = tc.repository.createSession(
            projectID: projectID, meetingDate: meetingDate, chapterOrPages: "Chapter 5",
            notes: "Discussed character development", agendaItems: ["Review chapter", "Discuss themes"]
        )

        #expect(session.meetingDate == meetingDate)
        #expect(session.chapterOrPages == "Chapter 5")
        #expect(session.latestUnifiedNoteText == "Discussed character development")
        #expect(session.agendaItems == ["Review chapter", "Discuss themes"])
    }

    @Test("createSession persists to context")
    func createSessionPersistsToContext() throws {
        let tc = try RepositoryTestContext.make()
        let session = tc.repository.createSession(projectID: UUID())
        let fetched = tc.repository.fetchSession(id: session.id)

        #expect(fetched != nil)
        #expect(fetched?.id == session.id)
    }
}

// MARK: - Session Update Tests

@Suite("ProjectRepository Session Update Tests", .serialized)
@MainActor
struct ProjectRepositorySessionUpdateTests {

    @Test("updateSession updates meetingDate")
    func updateSessionUpdatesMeetingDate() throws {
        let tc = try RepositoryTestContext.make()
        let session = ProjectSession(projectID: UUID())
        tc.context.insert(session)
        try tc.context.save()

        let newDate = TestCalendar.date(year: 2025, month: 3, day: 20)
        let result = tc.repository.updateSession(id: session.id, meetingDate: newDate)

        #expect(result == true)
        #expect(session.meetingDate == newDate)
    }

    @Test("updateSession updates chapterOrPages")
    func updateSessionUpdatesChapterOrPages() throws {
        let tc = try RepositoryTestContext.make()
        let session = ProjectSession(projectID: UUID())
        tc.context.insert(session)
        try tc.context.save()

        let result = tc.repository.updateSession(id: session.id, chapterOrPages: "Pages 50-75")

        #expect(result == true)
        #expect(session.chapterOrPages == "Pages 50-75")
    }

    @Test("updateSession clears chapterOrPages when empty")
    func updateSessionClearsChapterOrPages() throws {
        let tc = try RepositoryTestContext.make()
        let session = ProjectSession(projectID: UUID(), chapterOrPages: "Chapter 1")
        tc.context.insert(session)
        try tc.context.save()

        let result = tc.repository.updateSession(id: session.id, chapterOrPages: "")

        #expect(result == true)
        #expect(session.chapterOrPages == nil)
    }

    @Test("updateSession returns false for missing ID")
    func updateSessionReturnsFalseForMissingId() throws {
        let tc = try RepositoryTestContext.make()
        let result = tc.repository.updateSession(id: UUID(), notes: "Test")

        #expect(result == false)
    }
}

// MARK: - Session Delete Tests

@Suite("ProjectRepository Session Delete Tests", .serialized)
@MainActor
struct ProjectRepositorySessionDeleteTests {

    @Test("deleteSession removes session from context")
    func deleteSessionRemovesFromContext() throws {
        let tc = try RepositoryTestContext.make()
        let session = ProjectSession(projectID: UUID())
        tc.context.insert(session)
        try tc.context.save()
        let sessionID = session.id

        try tc.repository.deleteSession(id: sessionID)

        #expect(tc.repository.fetchSession(id: sessionID) == nil)
    }

    @Test("deleteSession does nothing for missing ID")
    func deleteSessionDoesNothingForMissingId() throws {
        let tc = try RepositoryTestContext.make()
        try tc.repository.deleteSession(id: UUID())
        // Should not throw
    }
}

// MARK: - Template Tests

@Suite("ProjectRepository Template Tests", .serialized)
@MainActor
struct ProjectRepositoryTemplateTests {

    @Test("fetchTemplate returns template by ID")
    func fetchTemplateReturnsById() throws {
        let tc = try RepositoryTestContext.make()
        let template = ProjectAssignmentTemplate(projectID: UUID(), title: "Book Report")
        tc.context.insert(template)
        try tc.context.save()

        let fetched = tc.repository.fetchTemplate(id: template.id)

        #expect(fetched != nil)
        #expect(fetched?.title == "Book Report")
    }

    @Test("fetchTemplates forProjectID filters correctly")
    func fetchTemplatesForProjectIDFilters() throws {
        let tc = try RepositoryTestContext.make()
        let projectID1 = UUID()
        let projectID2 = UUID()

        tc.context.insert(ProjectAssignmentTemplate(projectID: projectID1, title: "Template 1"))
        tc.context.insert(ProjectAssignmentTemplate(projectID: projectID2, title: "Template 2"))
        try tc.context.save()

        let fetched = tc.repository.fetchTemplates(forProjectID: projectID1)

        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Template 1")
    }

    @Test("createTemplate creates template with required fields")
    func createTemplateCreatesWithRequiredFields() throws {
        let tc = try RepositoryTestContext.make()
        let template = tc.repository.createTemplate(projectID: UUID(), title: "Discussion Guide")

        #expect(template.title == "Discussion Guide")
        #expect(template.isShared == true)
    }

    @Test("createTemplate sets optional fields")
    func createTemplateSetsOptionalFields() throws {
        let tc = try RepositoryTestContext.make()
        let projectID = UUID()
        let lessonID = UUID()

        let template = tc.repository.createTemplate(
            projectID: projectID, title: "Book Report",
            instructions: "Write a 2-page summary", isShared: false,
            defaultLinkedLessonID: lessonID
        )

        #expect(template.instructions == "Write a 2-page summary")
        #expect(template.isShared == false)
        #expect(template.defaultLinkedLessonID == lessonID.uuidString)
    }

    @Test("deleteTemplate removes template from context")
    func deleteTemplateRemovesFromContext() throws {
        let tc = try RepositoryTestContext.make()
        let template = ProjectAssignmentTemplate(projectID: UUID(), title: "Template")
        tc.context.insert(template)
        try tc.context.save()
        let templateID = template.id

        try tc.repository.deleteTemplate(id: templateID)

        #expect(tc.repository.fetchTemplate(id: templateID) == nil)
    }
}

#endif
