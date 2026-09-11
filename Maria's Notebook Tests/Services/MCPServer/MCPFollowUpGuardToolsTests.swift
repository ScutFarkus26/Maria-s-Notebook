import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// The duplicate guard on `add_follow_up`: an identical open todo from today
/// is reported rather than added again, and `force` overrides it.
@Suite("MCP Follow-Up Duplicate Guard")
@MainActor
struct MCPFollowUpGuardToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func todos(in context: NSManagedObjectContext) -> [CDTodoItem] {
        context.safeFetch(CDFetchRequest(CDTodoItem.self))
    }

    @Test("add_follow_up reports an identical open todo from today and adds nothing")
    func duplicateFollowUpIsReported() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let add = try tool(named: "add_follow_up", in: tools)

        let arguments: [String: JSONValue] = [
            "title": .string("Call Ora's mother about the going out"),
            "student_names": .array([.string("Ora")])
        ]
        _ = try await add.handler(arguments)
        let todo = try #require(todos(in: context).first)
        let id = try #require(todo.id).uuidString

        let second = try await add.handler(arguments)
        #expect(second.contains("already exists"))
        #expect(second.contains("[todo id=\(id)]"))
        #expect(second.contains("force: true"))
        #expect(todos(in: context).count == 1)
        #expect(todo.isCompleted == false)
    }

    @Test("add_follow_up with force adds the second copy")
    func forceBypassesFollowUpGuard() async throws {
        let (tools, context) = try makeTools()
        let add = try tool(named: "add_follow_up", in: tools)
        let arguments: [String: JSONValue] = ["title": .string("Reorder the pink tower cards")]

        _ = try await add.handler(arguments)
        var forced = arguments
        forced["force"] = .bool(true)
        let receipt = try await add.handler(forced)

        #expect(receipt.contains("Added follow-up"))
        #expect(todos(in: context).count == 2)
    }

    @Test("a completed todo, or one about other children, is not a duplicate")
    func followUpGuardComparesStateAndStudents() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)
        let add = try tool(named: "add_follow_up", in: tools)

        _ = try await add.handler([
            "title": .string("Show the checkerboard again"),
            "student_names": .array([.string("Ora")])
        ])
        _ = try await add.handler([
            "title": .string("Show the checkerboard again"),
            "student_names": .array([.string("Etty")])
        ])
        #expect(todos(in: context).count == 2)

        for todo in todos(in: context) {
            todo.isCompleted = true
            todo.completedAt = Date()
        }
        CoreDataTestHelpers.save(context)

        // A finished follow-up is not in the way: the guide is asking for the next one.
        _ = try await add.handler([
            "title": .string("Show the checkerboard again"),
            "student_names": .array([.string("Ora")])
        ])
        #expect(todos(in: context).count == 3)
    }
}
