import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What the check-in suites share: an in-memory notebook with the MCP tools,
/// and one lesson assigned with a check-in on 2026-09-18.
@MainActor
enum CheckInFixture {
    static func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    static func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    /// Each child's own row among `works`, keyed by first name.
    static func rowsByFirstName(
        _ works: [CDWorkModel], in context: NSManagedObjectContext
    ) -> [String: CDWorkModel] {
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        var rows: [String: CDWorkModel] = [:]
        for work in works {
            guard let owner = WorkGrouping.owner(of: work),
                  let student = students.first(where: { $0.id == owner }) else { continue }
            rows[student.firstName] = work
        }
        return rows
    }

    /// Assigns "Checkerboard practice" to `names` with a check-in on
    /// 2026-09-18 and returns each child's own row, keyed by first name.
    /// `beforeAssigning` runs once the lesson and children exist.
    static func assignWithCheckIn(
        to names: [String], tools: [MCPToolDefinition], context: NSManagedObjectContext,
        beforeAssigning: (CDLesson, [CDStudent]) -> Void = { _, _ in }
    ) async throws -> [String: CDWorkModel] {
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let students = names.map { CoreDataTestHelpers.seedStudent(in: context, firstName: $0, lastName: "Test") }
        beforeAssigning(lesson, students)
        CoreDataTestHelpers.save(context)
        _ = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array(names.map { .string($0) }),
            "title": .string("Checkerboard practice"),
            "check_in_date": .string("2026-09-18"),
            "check_in_purpose": .string("see the long multiplication laid out")
        ])
        let rows = rowsByFirstName(context.safeFetch(CDFetchRequest(CDWorkModel.self)), in: context)
        #expect(rows.count == names.count)
        return rows
    }

    static func id(of work: CDWorkModel) throws -> String {
        try #require(work.id).uuidString
    }

    /// The check-ins on one day, read back from the store.
    static func checkIns(
        of work: CDWorkModel, on dayText: String, in context: NSManagedObjectContext
    ) -> [CDWorkCheckIn] {
        let day = AppCalendar.startOfDay(MCPNotebookTools.isoDay.date(from: dayText)!)
        return MCPNotebookTools.checkIns(of: work, in: context)
            .filter { $0.date.map { AppCalendar.isSameDay($0, day) } ?? false }
    }

    static func message(from block: () async throws -> String) async -> String {
        do {
            _ = try await block()
            return ""
        } catch let error as MCPToolError {
            return error.message
        } catch {
            return "unexpected: \(error)"
        }
    }

    /// Runs one handler call inside a call outcome, as the request handler does.
    static func outcome(of call: () async throws -> String) async throws -> MCPCallOutcome {
        let outcome = MCPCallOutcome()
        _ = try await MCPCallOutcome.$current.withValue(outcome) { try await call() }
        return outcome
    }
}

/// update_work's check-in guards: never two check-ins on one day, a status
/// in the same call counts, a no-op stays out of the journal, and a child
/// who has left is left alone.
@Suite("MCP Work Check-In Guards")
@MainActor
struct MCPWorkCheckInGuardsTests {
    private typealias Fixture = CheckInFixture

    // MARK: - Moving onto a day that already has one (#15)

    @Test("moving onto a day that already has a check-in is refused, and nothing moves")
    func moveOntoTakenDayIsRefused() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])
        let update = try Fixture.tool(named: "update_work", in: tools)
        _ = try await update.handler([
            "work_id": .string(try Fixture.id(of: work)),
            "add_check_in_on": .string("2026-09-21")
        ])

        let refusal = await Fixture.message {
            try await update.handler([
                "work_id": .string(try Fixture.id(of: work)),
                "move_check_in_from": .string("2026-09-18"),
                "move_check_in_to": .string("2026-09-21")
            ])
        }
        #expect(refusal.contains("already has a scheduled check-in on 2026-09-21"))
        #expect(Fixture.checkIns(of: work, on: "2026-09-18", in: context).count == 1)
        #expect(Fixture.checkIns(of: work, on: "2026-09-21", in: context).count == 1)
    }

    @Test("a linked copy with a check-in on the new day stays where it is, and the reply says so")
    func moveLeavesSiblingWithCheckInOnLandingDay() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])
        let eli = try #require(rows["Eli"])
        let update = try Fixture.tool(named: "update_work", in: tools)
        _ = try await update.handler([
            "work_id": .string(try Fixture.id(of: eli)),
            "add_check_in_on": .string("2026-09-21"),
            "add_check_in_for_this_child_only": .bool(true)
        ])

        let receipt = try await update.handler([
            "work_id": .string(try Fixture.id(of: maya)),
            "move_check_in_from": .string("2026-09-18"),
            "move_check_in_to": .string("2026-09-21")
        ])
        #expect(receipt.contains("moved the check-in from 2026-09-18 to 2026-09-21"))
        #expect(receipt.contains(
            "Eli Test's linked copy [work id=\(try Fixture.id(of: eli))] already has a scheduled check-in on "
                + "2026-09-21, so its check-in stayed on 2026-09-18"
        ))
        #expect(Fixture.checkIns(of: maya, on: "2026-09-21", in: context).count == 1)
        #expect(Fixture.checkIns(of: eli, on: "2026-09-18", in: context).count == 1)
        #expect(Fixture.checkIns(of: eli, on: "2026-09-21", in: context).count == 1)
    }

    // MARK: - A status and a new check-in in one call (#17)

    @Test("reopening the work and adding a check-in in one call does both, on every linked copy")
    func reopenAndAddInOneCall() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])
        let eli = try #require(rows["Eli"])
        let update = try Fixture.tool(named: "update_work", in: tools)
        _ = try await update.handler(["work_id": .string(try Fixture.id(of: maya)), "status": .string("mastered")])
        #expect(maya.isClosed)
        #expect(eli.isClosed)

        let receipt = try await update.handler([
            "work_id": .string(try Fixture.id(of: maya)),
            "status": .string("active"),
            "add_check_in_on": .string("2026-09-24")
        ])
        #expect(receipt.contains("added a check-in on 2026-09-24"))
        #expect(receipt.contains("also added to Eli Test's linked copy"))
        #expect(!maya.isClosed)
        #expect(!eli.isClosed)
        // Added after the status was logged, so the log didn't settle it.
        #expect(Fixture.checkIns(of: maya, on: "2026-09-24", in: context).map(\.status) == [.scheduled])
        #expect(Fixture.checkIns(of: eli, on: "2026-09-24", in: context).map(\.status) == [.scheduled])
    }

    @Test("closing the work and adding a check-in in one call is refused, and neither happens")
    func closeAndAddInOneCallIsRefused() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])

        let refusal = await Fixture.message {
            try await Fixture.tool(named: "update_work", in: tools).handler([
                "work_id": .string(try Fixture.id(of: work)),
                "status": .string("mastered"),
                "add_check_in_on": .string("2026-09-24")
            ])
        }
        #expect(refusal.contains("which closes it, so it can't also get a new check-in"))
        #expect(!work.isClosed)
        #expect(Fixture.checkIns(of: work, on: "2026-09-24", in: context).isEmpty)
        #expect(!context.hasChanges)
    }

    // MARK: - An add that changes nothing (#18)

    @Test("an add that finds a check-in on the day everywhere stays out of the write journal")
    func addThatChangesNothingIsNotJournaled() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let mayaID = try Fixture.id(of: try #require(rows["Maya"]))
        let update = try Fixture.tool(named: "update_work", in: tools)

        let noOp = try await Fixture.outcome {
            try await update.handler(["work_id": .string(mayaID), "add_check_in_on": .string("2026-09-18")])
        }
        #expect(noOp.wroteNothing)

        let real = try await Fixture.outcome {
            try await update.handler(["work_id": .string(mayaID), "add_check_in_on": .string("2026-09-24")])
        }
        #expect(!real.wroteNothing)

        let withDueDate = try await Fixture.outcome {
            try await update.handler([
                "work_id": .string(mayaID),
                "add_check_in_on": .string("2026-09-18"),
                "due_date": .string("2026-09-30")
            ])
        }
        #expect(!withDueDate.wroteNothing)
    }

    // MARK: - A child who has left (#19)

    @Test("a linked copy of a child who has left gets no new check-in, keeps its day, and is named")
    func departedSiblingIsSkippedAndNamed() async throws {
        let (tools, context) = try Fixture.makeTools()
        let rows = try await Fixture.assignWithCheckIn(to: ["Maya", "Eli", "Ana"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])
        let eli = try #require(rows["Eli"])
        let ana = try #require(rows["Ana"])
        let anaStudent = try #require(
            context.safeFetch(CDFetchRequest(CDStudent.self)).first { $0.firstName == "Ana" }
        )
        anaStudent.enrollmentStatus = .withdrawn
        CoreDataTestHelpers.save(context)
        let update = try Fixture.tool(named: "update_work", in: tools)
        let anaLabel = "[work id=\(try Fixture.id(of: ana))] belongs to a child who has left the classroom"

        let added = try await update.handler([
            "work_id": .string(try Fixture.id(of: maya)),
            "add_check_in_on": .string("2026-09-24")
        ])
        #expect(added.contains("also added to Eli Test's linked copy"))
        #expect(added.contains("\(anaLabel), so it got no check-in"))
        #expect(Fixture.checkIns(of: eli, on: "2026-09-24", in: context).count == 1)
        #expect(Fixture.checkIns(of: ana, on: "2026-09-24", in: context).isEmpty)

        let moved = try await update.handler([
            "work_id": .string(try Fixture.id(of: maya)),
            "move_check_in_from": .string("2026-09-18"),
            "move_check_in_to": .string("2026-09-21")
        ])
        #expect(moved.contains("also moved Eli Test's linked copy"))
        #expect(moved.contains("\(anaLabel), so its check-in stayed on 2026-09-18"))
        #expect(Fixture.checkIns(of: ana, on: "2026-09-18", in: context).count == 1)
        #expect(Fixture.checkIns(of: ana, on: "2026-09-21", in: context).isEmpty)
    }
}
