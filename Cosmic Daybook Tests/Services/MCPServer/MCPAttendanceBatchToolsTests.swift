import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The batch forms of `mark_attendance`: several named students, and
/// `mark_all_present` for everyone else.
@Suite("MCP Attendance Batch Tool")
@MainActor
struct MCPAttendanceBatchToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func seedClassroom(in context: NSManagedObjectContext) {
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .leadGuide)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Dalia", lastName: "Roth")
        CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rivka", lastName: "Gold", enrollmentStatus: .withdrawn
        )
        CoreDataTestHelpers.save(context)
    }

    private func mark(_ name: String, _ status: String) -> JSONValue {
        .object(["student_name": .string(name), "status": .string(status)])
    }

    private func records(in context: NSManagedObjectContext) -> [CDAttendanceRecord] {
        context.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
    }

    @Test("mark_all_present marks the class present apart from the students named")
    func markAllPresentWithAnException() async throws {
        let (tools, context) = try makeTools()
        seedClassroom(in: context)

        let receipt = try await tool(named: "mark_attendance", in: tools).handler([
            "students": .array([mark("Ora", "absent")]),
            "mark_all_present": .bool(true),
            "date": .string("2026-09-14")
        ])
        #expect(receipt.contains("Attendance for 2026-09-14:"))
        #expect(receipt.contains("- Ora Levi — absent"))
        #expect(receipt.contains("- Etty Klein — present"))
        #expect(receipt.contains("- Dalia Roth — present"))
        #expect(receipt.contains("3 student(s) marked."))
        // A withdrawn child is not part of "everyone else".
        #expect(receipt.contains("Rivka") == false)

        let day = try await tool(named: "attendance_for_day", in: tools).handler([
            "date": .string("2026-09-14")
        ])
        #expect(day.contains("Absent (1): Ora Levi"))
        #expect(day.contains("Present (2): Dalia Roth, Etty Klein"))
    }

    @Test("several named students are marked in one call")
    func marksSeveralNamedStudents() async throws {
        let (tools, context) = try makeTools()
        seedClassroom(in: context)

        let receipt = try await tool(named: "mark_attendance", in: tools).handler([
            "students": .array([mark("Ora", "tardy"), mark("Etty", "leftEarly")]),
            "date": .string("2026-09-14")
        ])
        #expect(receipt.contains("- Ora Levi — tardy"))
        #expect(receipt.contains("- Etty Klein — left early"))
        #expect(receipt.contains("2 student(s) marked."))
        #expect(records(in: context).count == 2)
    }

    @Test("an unknown name fails the whole call and writes nothing")
    func unknownNameFailsTheWholeCall() async throws {
        let (tools, context) = try makeTools()
        seedClassroom(in: context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "mark_attendance", in: tools).handler([
                "students": .array([mark("Ora", "absent"), mark("Zeta", "present")]),
                "date": .string("2026-09-14")
            ])
        }
        #expect(records(in: context).isEmpty)
    }

    @Test("a bad status fails the whole call and writes nothing")
    func badStatusFailsTheWholeCall() async throws {
        let (tools, context) = try makeTools()
        seedClassroom(in: context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "mark_attendance", in: tools).handler([
                "students": .array([mark("Ora", "present"), mark("Etty", "hiding")]),
                "date": .string("2026-09-14")
            ])
        }
        #expect(records(in: context).isEmpty)
    }

    @Test("absence_reason and note are refused alongside the batch forms")
    func perStudentDetailIsRefusedInABatch() async throws {
        let (tools, context) = try makeTools()
        seedClassroom(in: context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "mark_attendance", in: tools).handler([
                "students": .array([mark("Ora", "absent")]),
                "absence_reason": .string("sick")
            ])
        }
        #expect(records(in: context).isEmpty)
    }

    @Test("the single form is unchanged")
    func singleFormStillWorks() async throws {
        let (tools, context) = try makeTools()
        seedClassroom(in: context)

        let receipt = try await tool(named: "mark_attendance", in: tools).handler([
            "student_name": .string("Ora"),
            "status": .string("absent"),
            "date": .string("2026-09-14"),
            "absence_reason": .string("sick")
        ])
        #expect(receipt == "Marked Ora Levi absent on 2026-09-14 (sick).")
        #expect(records(in: context).count == 1)
    }
}
