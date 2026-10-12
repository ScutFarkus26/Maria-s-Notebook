import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12, agent MC: a dated Someday todo that never reaches
// Today (#23), a tag filter that never matched (#24), archived book clubs,
// retired jobs and children who left (#29), and no-op replies journaled as
// writes (#20).

@Suite("MCP todos, library and jobs (Fix1012MC)")
@MainActor
struct MCPTodoLibraryToolsFix1012MCTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func call(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> String {
        let tool = try #require(tools.first { $0.name == name })
        return try await tool.handler(arguments)
    }

    /// The refusal's message, or a marker that the call didn't refuse.
    private func refusal(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async -> String {
        do {
            _ = try await call(name, arguments, in: tools)
            return "no refusal"
        } catch let error as MCPToolError {
            return error.message
        } catch {
            return "unexpected: \(error)"
        }
    }

    /// Runs one handler call inside a call outcome, as the request handler does.
    private func outcome(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> MCPCallOutcome {
        let outcome = MCPCallOutcome()
        _ = try await MCPCallOutcome.$current.withValue(outcome) {
            try await call(name, arguments, in: tools)
        }
        return outcome
    }

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    private func seedTodo(_ title: String, in context: NSManagedObjectContext) -> CDTodoItem {
        let todo = CDTodoItem(context: context)
        todo.title = title
        return todo
    }

    // MARK: - #23: a date takes a todo out of Someday, and Someday clears the date

    @Test("update_todo with a scheduled date takes a Someday todo out of Someday")
    func scheduledDateLeavesSomeday() async throws {
        let (tools, context) = try makeTools()
        let todo = seedTodo("Order more bead bars", in: context)
        todo.isSomeday = true
        #expect(CoreDataTestHelpers.save(context))

        let reply = try await call("update_todo", [
            "todo_id": .string(try #require(todo.id).uuidString),
            "scheduled_date": .string("2026-10-14")
        ], in: tools)

        #expect(todo.isSomeday == false)
        #expect(todo.scheduledDate.map { AppCalendar.isSameDay($0, day("2026-10-14")) } == true)
        #expect(reply.contains("out of someday"))
    }

    @Test("update_todo moving a todo to Someday clears its scheduled day but keeps the deadline")
    func somedayClearsScheduledDay() async throws {
        let (tools, context) = try makeTools()
        let todo = seedTodo("Call the frame shop", in: context)
        todo.scheduledDate = day("2026-10-14")
        todo.dueDate = day("2026-10-30")
        #expect(CoreDataTestHelpers.save(context))

        _ = try await call("update_todo", [
            "todo_id": .string(try #require(todo.id).uuidString),
            "is_someday": .bool(true)
        ], in: tools)

        #expect(todo.isSomeday)
        #expect(todo.scheduledDate == nil)
        #expect(todo.dueDate.map { AppCalendar.isSameDay($0, day("2026-10-30")) } == true)
    }

    @Test("update_todo refuses a scheduled date and Someday together, changing nothing")
    func scheduledDateAndSomedayRefused() async throws {
        let (tools, context) = try makeTools()
        let todo = seedTodo("Sort the art cupboard", in: context)
        #expect(CoreDataTestHelpers.save(context))

        let message = await refusal("update_todo", [
            "todo_id": .string(try #require(todo.id).uuidString),
            "scheduled_date": .string("2026-10-14"),
            "is_someday": .bool(true)
        ], in: tools)

        #expect(message.contains("someday"))
        #expect(todo.scheduledDate == nil)
        #expect(todo.isSomeday == false)
    }

    // MARK: - #24: the tag filter compares tag names

    @Test("list_todos filters by a tag's name and prints tag names without their color")
    func tagFilterMatchesName() async throws {
        let (tools, context) = try makeTools()
        let urgent = seedTodo("Fix the pin map", in: context)
        urgent.tagsArray = [TagHelper.createTag(name: "Urgent", color: .red)]
        let other = seedTodo("Plan the field trip", in: context)
        other.tagsArray = [TagHelper.createTag(name: "Planning", color: .green)]
        #expect(CoreDataTestHelpers.save(context))

        let output = try await call("list_todos", ["tag": .string("urgent")], in: tools)

        #expect(output.hasPrefix("1 todo(s):"))
        #expect(output.contains("Fix the pin map"))
        #expect(!output.contains("Plan the field trip"))
        #expect(output.contains("tags Urgent"))
        #expect(!output.contains("Urgent|Red"))
    }

    // MARK: - #29: archived book clubs, retired jobs, children who left

    @Test("book_club leaves archived sessions out unless finished ones are asked for")
    func bookClubHidesArchived() async throws {
        let (tools, context) = try makeTools()
        let active = CDBookClubSession(context: context)
        active.displayName = "Charlotte's Web"
        active.status = .active
        let archived = CDBookClubSession(context: context)
        archived.displayName = "The Hobbit"
        archived.status = .archived
        #expect(CoreDataTestHelpers.save(context))

        let current = try await call("book_club", [:], in: tools)
        #expect(current.contains("Charlotte's Web"))
        #expect(!current.contains("The Hobbit"))

        let everything = try await call("book_club", ["include_finished": .bool(true)], in: tools)
        #expect(everything.contains("The Hobbit"))
    }

    private func seedJob(_ name: String, active: Bool, in context: NSManagedObjectContext) -> CDClassroomJob {
        let job = CDClassroomJob(context: context)
        job.id = UUID()
        job.name = name
        job.isActive = active
        job.maxStudents = 2
        return job
    }

    @Test("assign_job refuses a retired job and a child who has left")
    func assignJobRefusesRetiredAndDeparted() async throws {
        let (tools, context) = try makeTools()
        _ = seedJob("Chalkboards", active: false, in: context)
        _ = seedJob("Plant Care", active: true, in: context)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Tess", lastName: "Oyelaran")
        CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Naomi", lastName: "Reyes", enrollmentStatus: .withdrawn
        )
        #expect(CoreDataTestHelpers.save(context))

        let retired = await refusal("assign_job", [
            "job": .string("Chalkboards"), "student_name": .string("Tess"), "week_of": .string("2026-10-14")
        ], in: tools)
        #expect(retired.contains("retired"))

        let departed = await refusal("assign_job", [
            "job": .string("Plant Care"), "student_name": .string("Naomi"), "week_of": .string("2026-10-14")
        ], in: tools)
        #expect(departed.contains("assign_job refused"))
        #expect(context.safeFetch(CDFetchRequest(CDJobAssignment.self)).isEmpty)
    }

    // MARK: - #20: replies that change nothing stay out of the write journal

    @Test("assign_job's already-has and empty-clear replies are not journaled as writes")
    func assignJobNoOpsWriteNothing() async throws {
        let (tools, context) = try makeTools()
        _ = seedJob("Plant Care", active: true, in: context)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Tess", lastName: "Oyelaran")
        #expect(CoreDataTestHelpers.save(context))
        let assign: [String: JSONValue] = [
            "job": .string("Plant Care"), "student_name": .string("Tess"), "week_of": .string("2026-10-14")
        ]

        let clearEmpty = try await outcome("assign_job", [
            "job": .string("Plant Care"), "clear": .bool(true), "week_of": .string("2026-10-21")
        ], in: tools)
        #expect(clearEmpty.wroteNothing)

        let first = try await outcome("assign_job", assign, in: tools)
        #expect(!first.wroteNothing)
        let again = try await outcome("assign_job", assign, in: tools)
        #expect(again.wroteNothing)
    }

    @Test("adjust_supply's already-at reply is not journaled as a write")
    func adjustSupplyNoOpWritesNothing() async throws {
        let (tools, context) = try makeTools()
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = "Paper Towels"
        supply.currentQuantity = 6
        #expect(CoreDataTestHelpers.save(context))

        let same = try await outcome("adjust_supply", [
            "supply": .string("Paper Towels"), "set_to": .int(6)
        ], in: tools)
        #expect(same.wroteNothing)
    }
}
