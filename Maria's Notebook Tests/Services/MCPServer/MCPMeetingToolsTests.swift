import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("MCP Meeting & Follow-Up Tools")
@MainActor
struct MCPMeetingToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        return (tools, context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    // MARK: - create_meeting_entry

    @Test("create_meeting_entry writes a completed meeting with goals as focus items")
    func createMeetingEntryWritesMeetingAndGoals() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let studentID = try #require(student.id)

        let output = try await tool(named: "create_meeting_entry", in: tools).handler([
            "student": .string("Ora"),
            "date": .string("2026-08-27"),
            "reflection": .string("Working through Skyscrapers drawers with Avital."),
            "lesson_requests": .string("Racks and tubes; division on paper soon."),
            "goals": .array([.string("Finish racks and tubes"), .string("Pick a civilization")])
        ])
        #expect(output.contains("Ora Levi"))
        #expect(output.contains("2026-08-27"))
        #expect(output.contains("2 new goal(s)"))

        let meetings = context.safeFetch(CDFetchRequest(CDStudentMeeting.self))
        #expect(meetings.count == 1)
        let meeting = try #require(meetings.first)
        #expect(meeting.studentIDUUID == studentID)
        #expect(meeting.completed)
        #expect(meeting.reflection == "Working through Skyscrapers drawers with Avital.")
        #expect(meeting.requests == "Racks and tubes; division on paper soon.")
        #expect(meeting.focus.contains("Finish racks and tubes"))

        let focusItems = FocusItemService.fetchActive(studentID: studentID, context: context)
        #expect(focusItems.count == 2)
        #expect(focusItems.allSatisfy { $0.createdInMeetingIDUUID == meeting.id })
    }

    @Test("create_meeting_entry rejects an entry with no content")
    func createMeetingEntryRejectsEmptyContent() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "create_meeting_entry", in: tools).handler([
                "student": .string("Ora")
            ])
        }
        #expect(context.safeFetch(CDFetchRequest(CDStudentMeeting.self)).isEmpty)
    }

    @Test("create_meeting_entry rejects a malformed date")
    func createMeetingEntryRejectsBadDate() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "create_meeting_entry", in: tools).handler([
                "student": .string("Ora"),
                "date": .string("yesterday"),
                "reflection": .string("Should not save.")
            ])
        }
        #expect(context.safeFetch(CDFetchRequest(CDStudentMeeting.self)).isEmpty)
    }

    // MARK: - add_follow_up

    @Test("add_follow_up creates a todo tied to students with a due date")
    func addFollowUpCreatesTodo() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Katz")
        CoreDataTestHelpers.save(context)
        let studentID = try #require(student.id)

        let output = try await tool(named: "add_follow_up", in: tools).handler([
            "title": .string("Order Ellis Island books"),
            "notes": .string("Project is stalled until these land."),
            "student_names": .array([.string("Etty")]),
            "due_date": .string("2026-09-10")
        ])
        #expect(output.contains("Order Ellis Island books"))
        #expect(output.contains("due 2026-09-10"))
        #expect(output.contains("Etty Katz"))

        let todos = context.safeFetch(CDFetchRequest(CDTodoItem.self))
        #expect(todos.count == 1)
        let todo = try #require(todos.first)
        #expect(todo.title == "Order Ellis Island books")
        #expect(todo.studentIDsArray == [studentID.uuidString])
        #expect(!todo.isCompleted)
        #expect(todo.dueDate != nil)
    }

    // MARK: - resolve_follow_up

    @Test("resolve_follow_up completes a todo by id")
    func resolveFollowUpCompletesTodo() async throws {
        let (tools, context) = try makeTools()
        _ = try await tool(named: "add_follow_up", in: tools).handler([
            "title": .string("Check I Survived titles in the library")
        ])
        let todo = try #require(context.safeFetch(CDFetchRequest(CDTodoItem.self)).first)
        let todoID = try #require(todo.id?.uuidString)

        let output = try await tool(named: "resolve_follow_up", in: tools).handler([
            "id": .string(todoID)
        ])
        #expect(output.contains("Completed follow-up"))
        #expect(todo.isCompleted)
        #expect(todo.completedAt != nil)
    }

    @Test("resolve_follow_up resolves a student goal by id")
    func resolveFollowUpResolvesFocusItem() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Dalia", lastName: "Roth")
        CoreDataTestHelpers.save(context)
        let studentID = try #require(student.id)

        let item = FocusItemService.create(
            studentID: studentID,
            text: "Get back into algebra",
            meetingID: UUID(),
            sortOrder: 0,
            context: context
        )
        CoreDataTestHelpers.save(context)
        let itemID = try #require(item.id?.uuidString)

        let output = try await tool(named: "resolve_follow_up", in: tools).handler([
            "id": .string(itemID)
        ])
        #expect(output.contains("Resolved goal"))
        #expect(item.isResolved)
        #expect(item.resolvedAt != nil)
    }

    @Test("resolve_follow_up reports an unknown id without saving")
    func resolveFollowUpRejectsUnknownID() async throws {
        let (tools, _) = try makeTools()
        do {
            _ = try await tool(named: "resolve_follow_up", in: tools).handler([
                "id": .string(UUID().uuidString)
            ])
            Issue.record("Expected an unknown-id error")
        } catch let error as MCPToolError {
            #expect(error.message.contains("was found"))
        }
    }

    // MARK: - list_open_follow_ups

    @Test("list_open_follow_ups reports todos, goals, and flagged notes")
    func listOpenFollowUpsReportsAllSections() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Katz")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "add_follow_up", in: tools).handler([
            "title": .string("Order Morse code books"),
            "student_names": .array([.string("Etty")])
        ])
        _ = try await tool(named: "create_meeting_entry", in: tools).handler([
            "student": .string("Etty"),
            "goals": .array([.string("Narrative writing from the Ellis Island trip")])
        ])
        _ = try await tool(named: "create_observation", in: tools).handler([
            "student_names": .array([.string("Etty")]),
            "body": .string("Opened five threads in one meeting."),
            "needs_follow_up": .bool(true)
        ])

        let output = try await tool(named: "list_open_follow_ups", in: tools).handler([:])
        #expect(output.contains("Follow-up todos:"))
        #expect(output.contains("Order Morse code books"))
        #expect(output.contains("Open student goals:"))
        #expect(output.contains("Narrative writing from the Ellis Island trip"))
        #expect(output.contains("Notes flagged for follow-up:"))
        #expect(output.contains("Opened five threads"))

        let filtered = try await tool(named: "list_open_follow_ups", in: tools).handler([
            "student_name": .string("Etty")
        ])
        #expect(filtered.contains("Order Morse code books"))

        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Zell")
        CoreDataTestHelpers.save(context)
        let unrelated = try await tool(named: "list_open_follow_ups", in: tools).handler([
            "student_name": .string("Sarah")
        ])
        #expect(unrelated.contains("Nothing is open for Sarah Zell."))
    }
}
