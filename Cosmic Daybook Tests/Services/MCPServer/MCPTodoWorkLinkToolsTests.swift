import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Todo Work Links")
@MainActor
struct MCPTodoWorkLinkToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func call(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> String {
        let tool = try #require(tools.first { $0.name == name })
        return try await tool.handler(arguments)
    }

    private func onlyTodo(in context: NSManagedObjectContext) throws -> CDTodoItem {
        try #require(context.safeFetch(CDFetchRequest(CDTodoItem.self)).first)
    }

    private func seedWork(_ title: String, in context: NSManagedObjectContext) throws -> String {
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: title)
        CoreDataTestHelpers.save(context)
        return try #require(work.id).uuidString
    }

    // MARK: - add_follow_up

    @Test("add_follow_up stores work_id as the work's uuid string")
    func addFollowUpLinksWork() async throws {
        let (tools, context) = try makeTools()
        let workID = try seedWork("Map of Africa", in: context)

        let receipt = try await call("add_follow_up", [
            "title": .string("Check in on the map"),
            "work_id": .string(workID.lowercased())
        ], in: tools)

        #expect(try onlyTodo(in: context).linkedWorkItemID == workID)
        #expect(receipt.contains("linked to work \"Map of Africa\""))
    }

    @Test("add_follow_up refuses a work_id that names no work, and saves nothing")
    func addFollowUpRejectsUnknownWork() async throws {
        let (tools, context) = try makeTools()
        let missing = UUID().uuidString

        await #expect(throws: MCPToolError.self) {
            _ = try await call("add_follow_up", [
                "title": .string("Check in"), "work_id": .string(missing)
            ], in: tools)
        }
        await #expect(throws: MCPToolError.self) {
            _ = try await call("add_follow_up", [
                "title": .string("Check in"), "work_id": .string("map work")
            ], in: tools)
        }
        #expect(context.safeFetch(CDFetchRequest(CDTodoItem.self)).isEmpty)
    }

    @Test("add_follow_up without work_id leaves the todo unlinked")
    func addFollowUpWithoutWork() async throws {
        let (tools, context) = try makeTools()
        _ = try await call("add_follow_up", ["title": .string("Order paint")], in: tools)
        #expect(try onlyTodo(in: context).linkedWorkItemID == nil)
    }

    // MARK: - update_todo

    @Test("update_todo sets, then clears, the work link")
    func updateTodoSetsAndClears() async throws {
        let (tools, context) = try makeTools()
        let workID = try seedWork("Bead chains", in: context)
        _ = try await call("add_follow_up", ["title": .string("See the hundred chain")], in: tools)
        let todo = try onlyTodo(in: context)
        let todoID = try #require(todo.id).uuidString

        let linked = try await call("update_todo", [
            "todo_id": .string(todoID), "work_id": .string(workID)
        ], in: tools)
        #expect(todo.linkedWorkItemID == workID)
        #expect(linked.contains("linked to work \"Bead chains\""))

        let cleared = try await call("update_todo", [
            "todo_id": .string(todoID), "clear_work_id": .bool(true)
        ], in: tools)
        #expect(todo.linkedWorkItemID == nil)
        #expect(cleared.contains("unlinked"))
    }

    @Test("update_todo treats a blank or null work_id as a clear")
    func updateTodoBlankOrNullClears() async throws {
        let (tools, context) = try makeTools()
        let workID = try seedWork("Bead chains", in: context)
        _ = try await call("add_follow_up", [
            "title": .string("See the chain"), "work_id": .string(workID)
        ], in: tools)
        let todo = try onlyTodo(in: context)
        let todoID = try #require(todo.id).uuidString

        _ = try await call("update_todo", ["todo_id": .string(todoID), "work_id": .string("")], in: tools)
        #expect(todo.linkedWorkItemID == nil)

        todo.linkedWorkItemID = workID
        CoreDataTestHelpers.save(context)
        _ = try await call("update_todo", ["todo_id": .string(todoID), "work_id": .null], in: tools)
        #expect(todo.linkedWorkItemID == nil)
    }

    @Test("update_todo refuses an unknown work and a work_id with clear_work_id, changing nothing")
    func updateTodoRejectsBadWork() async throws {
        let (tools, context) = try makeTools()
        let workID = try seedWork("Bead chains", in: context)
        _ = try await call("add_follow_up", [
            "title": .string("See the chain"), "work_id": .string(workID)
        ], in: tools)
        let todo = try onlyTodo(in: context)
        let todoID = try #require(todo.id).uuidString

        await #expect(throws: MCPToolError.self) {
            _ = try await call("update_todo", [
                "todo_id": .string(todoID), "title": .string("Renamed"),
                "work_id": .string(UUID().uuidString)
            ], in: tools)
        }
        await #expect(throws: MCPToolError.self) {
            _ = try await call("update_todo", [
                "todo_id": .string(todoID), "work_id": .string(workID), "clear_work_id": .bool(true)
            ], in: tools)
        }
        #expect(todo.linkedWorkItemID == workID)
        #expect(todo.title == "See the chain")
    }

    // MARK: - Reads

    @Test("list_todos and list_open_follow_ups show the linked work id and title")
    func readsShowLinkedWork() async throws {
        let (tools, context) = try makeTools()
        let workID = try seedWork("Timeline of life", in: context)
        _ = try await call("add_follow_up", [
            "title": .string("Ask about the timeline"), "work_id": .string(workID)
        ], in: tools)

        let listed = try await call("list_todos", [:], in: tools)
        #expect(listed.contains("linked_work_id=\(workID) \"Timeline of life\""))

        let followUps = try await call("list_open_follow_ups", [:], in: tools)
        #expect(followUps.contains("linked_work_id=\(workID)"))
    }

    @Test("A todo whose work was deleted says so")
    func readsFlagMissingWork() async throws {
        let (tools, context) = try makeTools()
        _ = try await call("add_follow_up", ["title": .string("Ask about it")], in: tools)
        let gone = UUID().uuidString
        try onlyTodo(in: context).linkedWorkItemID = gone
        CoreDataTestHelpers.save(context)

        let listed = try await call("list_todos", [:], in: tools)
        #expect(listed.contains("linked_work_id=\(gone) (work not found)"))
    }
}
