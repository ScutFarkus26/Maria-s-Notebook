import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Review of the 2026-10-12 MCP fixes, round B: (#1, the monthly-report guard on
// updates, went with Parent Reports in 2026-11), a todo both dated and someday (#2, #12), and completed_by
// beside a status or on a child's own copy (#3, #10). The case-only rename
// (#4), record batches (#5), attendance batches (#6, #7), completed
// check-ins' todos (#8) and descriptions (#9) are in
// MCPToolsTests+Fix1012ReviewB2.swift; #11 is in MCPToolsTests+Fix1012MR.swift.

@Suite("MCP tools review B (Fix1012ReviewB)")
@MainActor
struct MCPToolsFix1012ReviewBTests {
    private typealias Fixture = CheckInFixture

    private func call(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> String {
        try await Fixture.tool(named: name, in: tools).handler(arguments)
    }

    private func refusal(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async -> String {
        await Fixture.message { try await call(name, arguments, in: tools) }
    }

    /// The reply, and whether the call stayed out of the write journal.
    private func outcome(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> (reply: String, wroteNothing: Bool) {
        let tool = try Fixture.tool(named: name, in: tools)
        var reply = ""
        let outcome = try await Fixture.outcome {
            reply = try await tool.handler(arguments)
            return reply
        }
        return (reply, outcome.wroteNothing)
    }

    // MARK: - #2: add_follow_up with a day and someday

    @Test("add_follow_up refuses a scheduled date and someday together, filing nothing")
    func followUpRefusesDayAndSomeday() async throws {
        let (tools, context) = try Fixture.makeTools()

        let message = await refusal("add_follow_up", [
            "title": .string("Rebuild the botany shelf"),
            "scheduled_date": .string("2026-10-14"),
            "is_someday": .bool(true)
        ], in: tools)

        #expect(message.contains("not both"))
        #expect(context.safeFetch(CDFetchRequest(CDTodoItem.self)).isEmpty)
    }

    // MARK: - #3 / #10: completed_by

    /// One row Avigail and Leshem share, the shape completed_by is for.
    private func seedSharedRow(in context: NSManagedObjectContext) throws -> CDWorkModel {
        let avigail = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avigail", lastName: "Green")
        let leshem = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leshem", lastName: "Pardes")
        let row = CoreDataTestHelpers.seedWorkModel(in: context, title: "Poster", studentID: try #require(avigail.id))
        row.id = UUID()
        for student in [avigail, leshem] {
            let participant = CDWorkParticipantEntity(context: context)
            participant.id = UUID()
            participant.studentID = try #require(student.id).uuidString
            participant.work = row
        }
        #expect(CoreDataTestHelpers.save(context))
        return row
    }

    @Test("completed_by beside a closing status is refused, and neither is recorded")
    func completedByWithClosingStatusIsRefused() async throws {
        let (tools, context) = try Fixture.makeTools()
        let row = try seedSharedRow(in: context)

        let message = await refusal("update_work", [
            "work_id": .string(try Fixture.id(of: row)),
            "completed_by": .string("Leshem"),
            "status": .string("mastered"),
            "note": .string("Finished the lettering.")
        ], in: tools)

        #expect(message.contains("completed_by"))
        #expect(message.contains("status"))
        #expect(context.safeFetch(CDFetchRequest(CDWorkCompletionRecord.self)).isEmpty)
        #expect(!row.isClosed)
    }

    @Test("completed_by naming the owner of a linked copy is refused and points to status")
    func completedByOwnerOfLinkedCopyIsRefused() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])

        let message = await refusal("update_work", [
            "work_id": .string(try Fixture.id(of: maya)),
            "completed_by": .string("Maya")
        ], in: tools)

        #expect(message.contains("status"))
        #expect(context.safeFetch(CDFetchRequest(CDWorkCompletionRecord.self)).isEmpty)
        #expect(!maya.isClosed)
    }

    @Test("completed_by naming the only child on the work is refused and points to status")
    func completedByOnlyChildIsRefused() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])

        let message = await refusal("update_work", [
            "work_id": .string(try Fixture.id(of: maya)),
            "completed_by": .string("Maya")
        ], in: tools)

        #expect(message.contains("status"))
        #expect(context.safeFetch(CDFetchRequest(CDWorkCompletionRecord.self)).isEmpty)
    }

    @Test("the classmate refusal on a linked copy doesn't assume who the child is")
    func classmateRefusalIsNeutral() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])

        let message = await refusal("update_work", [
            "work_id": .string(try Fixture.id(of: maya)),
            "completed_by": .string("Eli")
        ], in: tools)

        #expect(message.contains("their own copy"))
        #expect(!message.contains("her own"))
        #expect(!message.contains("her finish"))
    }

    // MARK: - #12: update_todo's When fields that change nothing

    @Test("update_todo moving a someday todo to someday changes nothing and writes nothing")
    func somedayNoOpWritesNothing() async throws {
        let (tools, context) = try Fixture.makeTools()
        let todo = CDTodoItem(context: context)
        todo.title = "Rebuild the botany shelf"
        todo.isSomeday = true
        #expect(CoreDataTestHelpers.save(context))
        let todoID = try #require(todo.id).uuidString

        let someday = try await outcome("update_todo", [
            "todo_id": .string(todoID), "is_someday": .bool(true)
        ], in: tools)
        #expect(someday.wroteNothing)
        #expect(!someday.reply.contains("moved to someday"))
        #expect(someday.reply.contains("nothing"))

        todo.isSomeday = false
        todo.scheduledDate = try CoreDataTestHelpers.day("2026-10-14")
        #expect(CoreDataTestHelpers.save(context))
        let sameDay = try await outcome("update_todo", [
            "todo_id": .string(todoID), "scheduled_date": .string("2026-10-14")
        ], in: tools)
        #expect(sameDay.wroteNothing)
        let notSomeday = try await outcome("update_todo", [
            "todo_id": .string(todoID), "is_someday": .bool(false)
        ], in: tools)
        #expect(notSomeday.wroteNothing)
        #expect(!notSomeday.reply.contains("moved out of someday"))

        let real = try await outcome("update_todo", [
            "todo_id": .string(todoID), "scheduled_date": .string("2026-10-15")
        ], in: tools)
        #expect(!real.wroteNothing)
        #expect(real.reply.contains("scheduled 2026-10-15"))
    }
}
