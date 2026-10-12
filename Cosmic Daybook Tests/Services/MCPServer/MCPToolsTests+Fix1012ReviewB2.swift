import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Review of the 2026-10-12 MCP fixes, round B, continued: a case-only rename
// of a twin (#4), a record batch's order (#5), attendance batches (#6, #7),
// the todos a completed check-in closes (#8) and what three descriptions
// promise (#9). The rest is in MCPToolsTests+Fix1012ReviewB.swift.

@Suite("MCP tools review B, continued (Fix1012ReviewB2)")
@MainActor
struct MCPToolsFix1012ReviewB2Tests {
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

    // MARK: - #4: a case-only rename of a pair filed before the check

    @Test("update_lesson lets a lesson of an old twin pair change only its capitals")
    func caseOnlyRenameOfOldTwinSaves() async throws {
        let (tools, context) = try Fixture.makeTools()
        let lower = CoreDataTestHelpers.seedLesson(
            in: context, name: "bead frame", area: "Math", sequence: "Operations"
        )
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame", area: "Math", sequence: "Operations")
        #expect(CoreDataTestHelpers.save(context))

        let receipt = try await call("update_lesson", [
            "lesson": .string(try #require(lower.id).uuidString),
            "name": .string("Bead Frame")
        ], in: tools)

        #expect(receipt.contains("renamed \"bead frame\" to \"Bead Frame\""))
        #expect(lower.name == "Bead Frame")
    }

    // MARK: - #5: a record batch is judged in date order

    private func givingOfCheckerboard(on day: String, purpose: String? = nil) -> JSONValue {
        var fields: [String: JSONValue] = [
            "lesson": .string("Checkerboard"), "student_names": .array([.string("Ora")]),
            "date": .string(day)
        ]
        if let purpose { fields["purpose"] = .string(purpose) }
        return .object(fields)
    }

    private func seedCheckerboardAndOra(in context: NSManagedObjectContext) {
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        #expect(CoreDataTestHelpers.save(context))
    }

    @Test("two givings listed latest first are held to the repeat guard as if in date order")
    func batchGuardIgnoresInputOrder() async throws {
        let (tools, context) = try Fixture.makeTools()
        seedCheckerboardAndOra(in: context)

        let message = await refusal("record_presentation", [
            "presentations": .array([
                givingOfCheckerboard(on: "2026-09-16"), givingOfCheckerboard(on: "2026-09-14")
            ])
        ], in: tools)

        #expect(message.hasPrefix("record_presentation refused — nothing has been changed."))
        #expect(context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).filter(\.isPresented).isEmpty)
    }

    @Test("a batch filed in date order still answers in the order it was given")
    func batchReceiptsKeepInputOrder() async throws {
        let (tools, context) = try Fixture.makeTools()
        seedCheckerboardAndOra(in: context)

        let output = try await call("record_presentation", [
            "presentations": .array([
                givingOfCheckerboard(on: "2026-09-16", purpose: "review"),
                givingOfCheckerboard(on: "2026-09-14")
            ])
        ], in: tools)

        let later = try #require(output.range(of: "on 2026-09-16"))
        let earlier = try #require(output.range(of: "on 2026-09-14"))
        #expect(later.lowerBound < earlier.lowerBound)
        #expect(context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).filter(\.isPresented).count == 2)
    }

    // MARK: - #6 / #7: attendance batches

    private func seedRoom(in context: NSManagedObjectContext) -> (maya: CDStudent, ora: CDStudent) {
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        #expect(CoreDataTestHelpers.save(context))
        return (maya, ora)
    }

    private func mark(_ name: String, _ status: String) -> JSONValue {
        .object(["student_name": .string(name), "status": .string(status)])
    }

    private func status(
        of student: CDStudent, on day: String, in context: NSManagedObjectContext
    ) throws -> AttendanceStatus {
        let id = try #require(student.id)
        return context.attendanceStatuses(for: [id], on: try CoreDataTestHelpers.day(day))[id] ?? .unmarked
    }

    @Test("a lone status present beside mark_all_present is ignored")
    func lonePresentStatusIsIgnored() async throws {
        let (tools, context) = try Fixture.makeTools()
        let room = seedRoom(in: context)

        let receipt = try await call("mark_attendance", [
            "status": .string("present"), "mark_all_present": .bool(true), "date": .string("2026-09-14")
        ], in: tools)

        #expect(try status(of: room.maya, on: "2026-09-14", in: context) == .present)
        #expect(try status(of: room.ora, on: "2026-09-14", in: context) == .present)
        #expect(receipt.contains("2 student(s) marked."))
    }

    @Test("a lone status that isn't present, with no child named, is refused")
    func loneOtherStatusIsRefused() async throws {
        let (tools, context) = try Fixture.makeTools()
        _ = seedRoom(in: context)

        let message = await refusal("mark_attendance", [
            "status": .string("absent"), "mark_all_present": .bool(true), "date": .string("2026-09-14")
        ], in: tools)

        #expect(message.contains("student_name"))
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).isEmpty)
    }

    @Test("a child named twice with two statuses is refused, nothing written")
    func childNamedTwiceWithTwoStatusesIsRefused() async throws {
        let (tools, context) = try Fixture.makeTools()
        _ = seedRoom(in: context)

        let message = await refusal("mark_attendance", [
            "students": .array([mark("Maya", "absent"), mark("Maya Stern", "tardy")]),
            "date": .string("2026-09-14")
        ], in: tools)
        #expect(message.contains("Maya Stern"))
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).isEmpty)

        let topLevel = await refusal("mark_attendance", [
            "students": .array([mark("Maya", "absent")]),
            "student_name": .string("Maya"), "status": .string("present"),
            "date": .string("2026-09-14")
        ], in: tools)
        #expect(topLevel.contains("Maya Stern"))
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).isEmpty)
    }

    @Test("a child named twice with one status is one mark, and the count says one")
    func identicalRepeatMerges() async throws {
        let (tools, context) = try Fixture.makeTools()
        let room = seedRoom(in: context)

        let receipt = try await call("mark_attendance", [
            "students": .array([mark("Maya", "absent"), mark("Maya Stern", "absent")]),
            "date": .string("2026-09-14")
        ], in: tools)

        #expect(try status(of: room.maya, on: "2026-09-14", in: context) == .absent)
        #expect(receipt.components(separatedBy: "- Maya Stern — absent").count - 1 == 1)
        #expect(receipt.contains("1 student(s) marked."))
    }

    // MARK: - #8: the todos a completed check-in closes

    @Test("complete_check_in_on names the linked todos it closes, and the description says it does")
    func completeCheckInNamesClosedTodos() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])
        let todo = CDTodoItem(context: context)
        todo.title = "See Maya's checkerboard"
        todo.linkedWorkItemID = try Fixture.id(of: work)
        #expect(CoreDataTestHelpers.save(context))

        let receipt = try await call("update_work", [
            "work_id": .string(try Fixture.id(of: work)),
            "complete_check_in_on": .string("2026-09-18")
        ], in: tools)

        #expect(todo.isCompleted)
        #expect(receipt.contains("\"See Maya's checkerboard\""))
        #expect(receipt.contains("[todo id=\(try #require(todo.id).uuidString)]"))
        let update = try Fixture.tool(named: "update_work", in: tools)
        #expect(update.description.contains("linked todos"))
        #expect(propertyDescription("complete_check_in_on", of: update).contains("linked todos"))
    }

    // MARK: - #9: what the descriptions promise

    private func propertyDescription(_ property: String, of tool: MCPToolDefinition) -> String {
        tool.inputSchema.objectValue?["properties"]?.objectValue?[property]?
            .objectValue?["description"]?.stringValue ?? ""
    }

    @Test("update_work's completed_by says it is for a shared row, not a child's own copy")
    func completedByDescriptionNamesTheRefusals() throws {
        let (tools, _) = try Fixture.makeTools()
        let text = propertyDescription("completed_by", of: try Fixture.tool(named: "update_work", in: tools))
        #expect(text.contains("linked copy"))
        #expect(text.contains("status"))
    }

    @Test("assign_job's description names the retired-job and departed-child refusals")
    func assignJobDescriptionNamesTheRefusals() throws {
        let (tools, _) = try Fixture.makeTools()
        let text = try Fixture.tool(named: "assign_job", in: tools).description
        #expect(text.contains("retired"))
        #expect(text.contains("left"))
    }

    @Test("list_reminders' description says only the synced list is shown")
    func listRemindersDescriptionNamesTheSyncedList() throws {
        let (tools, _) = try Fixture.makeTools()
        let text = try Fixture.tool(named: "list_reminders", in: tools).description
        #expect(text.contains("the one Reminders list chosen in Settings"))
    }

}
