import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What `list_projects` counts as a project, and who it counts as a member.
///
/// The live notebook had three projects, all created a year ago with no
/// sessions, and the tool called every one of them active — `isActive` is set
/// true at creation and never revisited, so it says "nobody pressed Mark
/// Complete", not "this is live". The member list has the mirror-image problem:
/// it keeps every child ever added, so two girls who have left the class were
/// still being read out as current members.
@Suite("MCP Project Tools")
@MainActor
struct MCPProjectToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    /// Dates are placed relative to the configured school-year boundary rather
    /// than as fixed calendar dates, so these stay true when the guide moves the
    /// year start in Settings — the rule is "this school year", not "365 days".
    private var yearStart: Date { ProjectActivity.currentYearStart() }
    private var lastYear: Date { yearStart.addingTimeInterval(-60 * 24 * 60 * 60) }
    private var thisYear: Date { yearStart.addingTimeInterval(24 * 60 * 60) }

    @discardableResult
    private func seedProject(
        in context: NSManagedObjectContext,
        title: String,
        members: [CDStudent],
        createdAt: Date,
        isActive: Bool = true
    ) -> CDProject {
        let project = CDProject(context: context)
        project.id = UUID()
        project.title = title
        project.isActive = isActive
        project.createdAt = createdAt
        project.modifiedAt = createdAt
        project.memberStudentIDsArray = members.compactMap { $0.id?.uuidString }
        return project
    }

    private func addSession(to project: CDProject, on date: Date, in context: NSManagedObjectContext) {
        let session = CDProjectSession(context: context)
        session.id = UUID()
        session.projectID = project.id?.uuidString ?? ""
        session.createdAt = date
        session.meetingDate = date
        session.project = project
    }

    // MARK: - Dormancy

    @Test("A year-old project with no sessions is not listed by default")
    func dormantProjectIsHiddenByDefault() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)
        seedProject(in: context, title: "Bird Study", members: [maya], createdAt: lastYear)
        #expect(CoreDataTestHelpers.save(context))

        let listing = try await tool(named: "list_projects", in: tools).handler([:])
        #expect(listing.hasPrefix("No projects."))
        // And it says where they went, rather than reading as an empty notebook.
        #expect(listing.contains("include_inactive"))
    }

    @Test("include_inactive names it and says how long it has been quiet")
    func dormantProjectIsNamedWhenAsked() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)
        seedProject(in: context, title: "Bird Study", members: [maya], createdAt: lastYear)
        #expect(CoreDataTestHelpers.save(context))

        let listing = try await tool(named: "list_projects", in: tools).handler([
            "include_inactive": .bool(true)
        ])
        #expect(listing.contains("Bird Study"))
        #expect(listing.contains("dormant since"))
    }

    @Test("A project that met this year is listed by default, with no label")
    func projectWithASessionThisYearIsActive() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)
        // Created long ago, but it has met since the year began.
        let project = seedProject(in: context, title: "Bird Study", members: [maya], createdAt: lastYear)
        addSession(to: project, on: thisYear, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let listing = try await tool(named: "list_projects", in: tools).handler([:])
        #expect(listing.contains("Bird Study"))
        #expect(!listing.contains("dormant"))
        #expect(listing.contains("Maya Soto"))
    }

    @Test("A project marked complete reads as closed, not dormant")
    func closedProjectSaysClosed() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)
        let project = seedProject(
            in: context, title: "Bird Study", members: [maya], createdAt: lastYear, isActive: false
        )
        addSession(to: project, on: thisYear, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let listing = try await tool(named: "list_projects", in: tools).handler([
            "include_inactive": .bool(true)
        ])
        #expect(listing.contains("closed"))
        #expect(!listing.contains("dormant"))
    }

    // MARK: - Members

    @Test("A withdrawn member is left out by default and marked when asked")
    func withdrawnMembersAreFilteredAndMarked() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let gone = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Brielle", lastName: "Frid", enrollmentStatus: .withdrawn
        )
        CoreDataTestHelpers.save(context)
        let project = seedProject(
            in: context, title: "Bird Study", members: [maya, gone], createdAt: lastYear
        )
        addSession(to: project, on: thisYear, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let listing = try await tool(named: "list_projects", in: tools).handler([:])
        #expect(listing.contains("Maya Soto"))
        #expect(!listing.contains("Brielle Frid"))

        let full = try await tool(named: "list_projects", in: tools).handler([
            "include_inactive": .bool(true)
        ])
        #expect(full.contains("Brielle Frid (former)"))
    }

    @Test("A project whose whole group has left says so")
    func allFormerMembersReadsAsNoCurrentMembers() async throws {
        let (tools, context) = try makeTools()
        let gone = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Maytal", lastName: "Meyer", enrollmentStatus: .transferred
        )
        CoreDataTestHelpers.save(context)
        let project = seedProject(in: context, title: "Bird Study", members: [gone], createdAt: lastYear)
        addSession(to: project, on: thisYear, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let listing = try await tool(named: "list_projects", in: tools).handler([:])
        #expect(listing.contains("no current members"))
    }

    @Test("Asking after a child who has left still finds her project")
    func studentFilterStillMatchesAFormerMember() async throws {
        let (tools, context) = try makeTools()
        let gone = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Maytal", lastName: "Meyer", enrollmentStatus: .withdrawn
        )
        CoreDataTestHelpers.save(context)
        seedProject(in: context, title: "Bird Study", members: [gone], createdAt: lastYear)
        #expect(CoreDataTestHelpers.save(context))

        // Membership filtering reads the raw id list on purpose: the question
        // "what was she part of" must still have an answer.
        let listing = try await tool(named: "list_projects", in: tools).handler([
            "student_name": .string("Maytal"),
            "include_inactive": .bool(true)
        ])
        #expect(listing.contains("Bird Study"))
        #expect(listing.contains("Maytal Meyer (former)"))
    }

    // MARK: - One project

    @Test("project_detail names every member, including the ones who left")
    func detailNamesFormerMembers() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let gone = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Brielle", lastName: "Frid", enrollmentStatus: .withdrawn
        )
        CoreDataTestHelpers.save(context)
        let project = seedProject(
            in: context, title: "Bird Study", members: [maya, gone], createdAt: lastYear
        )
        #expect(CoreDataTestHelpers.save(context))

        let detail = try await tool(named: "project_detail", in: tools).handler([
            "project_id": .string(try #require(project.id).uuidString)
        ])
        #expect(detail.contains("Maya Soto"))
        #expect(detail.contains("Brielle Frid (former)"))
        #expect(detail.contains("Dormant"))
    }
}
