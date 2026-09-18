import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `list_open_follow_ups` with `watching_only` shows exactly the app's
/// Watching list, and `resolve_follow_up` can clear a note's flag.
@Suite("MCP Watching Tools")
@MainActor
struct MCPWatchingToolsTests {

    private struct Fixture {
        let tools: [MCPToolDefinition]
        let context: NSManagedObjectContext
        let alice: UUID
        let flaggedNoteID: UUID
        let classNoteID: UUID
        let watchTodoID: UUID
        let callTodoID: UUID
        let goalID: UUID
    }

    private func makeFixture() throws -> Fixture {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        let alice = try #require(
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Alice", lastName: "Levi").id
        )

        let flagged = CoreDataTestHelpers.seedNote(in: context, body: "Alice needs the carries shown again.")
        flagged.scope = .student(alice)
        flagged.needsFollowUp = true
        let classNote = CoreDataTestHelpers.seedNote(in: context, body: "The class is loud after lunch.")
        classNote.scope = .all
        classNote.needsFollowUp = true

        let watch = CDTodoItem(context: context)
        watch.title = "Watch Alice with the stamp game"
        watch.studentUUIDs = [alice]
        let call = CDTodoItem(context: context)
        call.title = "Call parents"
        call.studentUUIDs = [alice]

        let goal = FocusItemService.create(
            studentID: alice, text: "Finish racks and tubes", meetingID: UUID(), sortOrder: 0, context: context
        )
        CoreDataTestHelpers.save(context)

        return Fixture(
            tools: tools, context: context, alice: alice,
            flaggedNoteID: try #require(flagged.id), classNoteID: try #require(classNote.id),
            watchTodoID: try #require(watch.id), callTodoID: try #require(call.id),
            goalID: try #require(goal.id)
        )
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    @Test("watching_only cites exactly the fetcher's rows and leaves the ordinary todo out")
    func watchingOnlyMatchesFetcher() async throws {
        let fixture: Fixture = try makeFixture()
        let output: String = try await tool(named: "list_open_follow_ups", in: fixture.tools)
            .handler(["watching_only": .bool(true)])

        let rows: [WatchItem] = WatchListFetcher.fetchAll(in: fixture.context)
        let expected: Set<UUID> = Set(rows.map(\.sourceID))
        let seeded: Set<UUID> = [fixture.flaggedNoteID, fixture.classNoteID, fixture.watchTodoID, fixture.goalID]
        #expect(expected == seeded)
        for id in expected {
            #expect(output.contains("id=\(id.uuidString)]"))
        }
        #expect(!output.contains(fixture.callTodoID.uuidString))
        #expect(output.contains("Alice Levi:"))
        #expect(output.contains("Whole class:"))
        #expect(output.contains("[note id=\(fixture.flaggedNoteID.uuidString)]"))
        #expect(output.contains("[todo id=\(fixture.watchTodoID.uuidString)]"))
        #expect(output.contains("[focusItem id=\(fixture.goalID.uuidString)]"))
        #expect(output.contains("touched "))
    }

    @Test("watching_only for one student omits whole-class notes")
    func watchingOnlyForStudent() async throws {
        let fixture = try makeFixture()
        let output = try await tool(named: "list_open_follow_ups", in: fixture.tools)
            .handler(["watching_only": .bool(true), "student_name": .string("Alice")])

        #expect(output.contains(fixture.flaggedNoteID.uuidString))
        #expect(output.contains(fixture.watchTodoID.uuidString))
        #expect(output.contains(fixture.goalID.uuidString))
        #expect(!output.contains(fixture.classNoteID.uuidString))
        #expect(!output.contains(fixture.callTodoID.uuidString))
        #expect(!output.contains("Whole class"))
    }

    @Test("The default form is unchanged: every open todo, goals, and flagged notes")
    func defaultFormStaysASuperset() async throws {
        let fixture = try makeFixture()
        let output = try await tool(named: "list_open_follow_ups", in: fixture.tools).handler([:])
        #expect(output.contains(fixture.callTodoID.uuidString))
        #expect(output.contains(fixture.watchTodoID.uuidString))
        #expect(output.contains(fixture.goalID.uuidString))
        #expect(output.contains(fixture.flaggedNoteID.uuidString))
        #expect(output.contains("Follow-up todos:"))
    }

    @Test("resolve_follow_up clears a note's flag, and says so again on a second call")
    func resolveFollowUpClearsNoteFlag() async throws {
        let fixture: Fixture = try makeFixture()
        let resolve: MCPToolDefinition = try tool(named: "resolve_follow_up", in: fixture.tools)
        let note: CDNote = try #require(fixture.context.object(CDNote.self, id: fixture.flaggedNoteID))
        let idString: String = fixture.flaggedNoteID.uuidString
        let arguments: [String: JSONValue] = ["id": .string(idString)]

        let first: String = try await resolve.handler(arguments)
        #expect(first.contains("Cleared the follow-up flag"))
        #expect(first.contains("[note id=\(idString)]"))
        #expect(note.needsFollowUp == false)

        let second: String = try await resolve.handler(arguments)
        #expect(second.contains("already cleared"))
        #expect(note.needsFollowUp == false)

        let watching: String = try await tool(named: "list_open_follow_ups", in: fixture.tools)
            .handler(["watching_only": .bool(true)])
        #expect(!watching.contains(idString))
    }

    @Test("resolve_follow_up resolves a goal through the service, with no meeting recorded")
    func resolveFollowUpResolvesGoal() async throws {
        let fixture = try makeFixture()
        let goal = try #require(fixture.context.object(CDStudentFocusItem.self, id: fixture.goalID))
        let output = try await tool(named: "resolve_follow_up", in: fixture.tools)
            .handler(["id": .string(fixture.goalID.uuidString)])
        #expect(output.contains("Resolved goal"))
        #expect(goal.status == .resolved)
        #expect(goal.resolvedAt != nil)
        #expect(goal.resolvedInMeetingID == nil)
    }

    @Test("resolve_follow_up still refuses an unknown id")
    func resolveFollowUpUnknownID() async throws {
        let fixture = try makeFixture()
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "resolve_follow_up", in: fixture.tools)
                .handler(["id": .string(UUID().uuidString)])
        }
    }
}
