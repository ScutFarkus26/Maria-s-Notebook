import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// update_work's check-in arguments: completing one and moving one.
///
/// Moves are verified the way a caller would verify them — by reading the
/// schedule back for both days — not by trusting the receipt alone.
@Suite("MCP Work Check-In Tools")
@MainActor
struct MCPWorkCheckInToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    /// Assigns one lesson to `names` with a check-in on 2026-09-18 and returns
    /// each child's own row, keyed by first name.
    private func assignWithCheckIn(
        to names: [String], tools: [MCPToolDefinition], context: NSManagedObjectContext
    ) async throws -> [String: CDWorkModel] {
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication")
        for name in names {
            CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Test")
        }
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "assign_work", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array(names.map { .string($0) }),
            "title": .string("Checkerboard practice"),
            "check_in_date": .string("2026-09-18"),
            "check_in_purpose": .string("see the long multiplication laid out")
        ])

        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        var rows: [String: CDWorkModel] = [:]
        for work in context.safeFetch(CDFetchRequest(CDWorkModel.self)) {
            guard let owner = WorkGrouping.owner(of: work),
                  let student = students.first(where: { $0.id == owner }) else { continue }
            rows[student.firstName] = work
        }
        #expect(rows.count == names.count)
        return rows
    }

    private func id(of work: CDWorkModel) throws -> String {
        try #require(work.id).uuidString
    }

    private func checkIns(of work: CDWorkModel, in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        MCPNotebookTools.checkIns(of: work, in: context)
    }

    private func day(_ text: String) -> Date {
        AppCalendar.startOfDay(MCPNotebookTools.isoDay.date(from: text)!)
    }

    /// The block of the schedule_for_range reply that belongs to one day.
    private func section(for dayText: String, in schedule: String) -> String {
        let lines = schedule.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.hasPrefix(dayText) }) else { return "" }
        let rest = lines[(start + 1)...]
        let header = #"^\d{4}-\d{2}-\d{2} \("#
        let end = rest.firstIndex(where: { $0.range(of: header, options: .regularExpression) != nil })
            ?? lines.endIndex
        return lines[start..<end].joined(separator: "\n")
    }

    private func message(from block: () async throws -> String) async -> String {
        do {
            _ = try await block()
            return ""
        } catch let error as MCPToolError {
            return error.message
        } catch {
            return "unexpected: \(error)"
        }
    }

    // MARK: - Moving

    @Test("moving a check-in shows on the new day and is gone from the old")
    func moveShowsOnNewDayAndLeavesOld() async throws {
        let (tools, context) = try makeTools()
        let rows = try await assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])

        let receipt = try await tool(named: "update_work", in: tools).handler([
            "work_id": .string(try id(of: work)),
            "move_check_in_from": .string("2026-09-18"),
            "move_check_in_to": .string("2026-09-21")
        ])
        #expect(receipt.contains("moved the check-in from 2026-09-18 to 2026-09-21"))

        let schedule = try await tool(named: "schedule_for_range", in: tools).handler([
            "start_date": .string("2026-09-18"),
            "end_date": .string("2026-09-21")
        ])
        #expect(!section(for: "2026-09-18", in: schedule).contains("Checkerboard practice"))
        let landed = section(for: "2026-09-21", in: schedule)
        #expect(landed.contains("Checkerboard practice"))
        #expect(landed.contains("(scheduled)"))

        // Only the day changed.
        let checkIn = try #require(checkIns(of: work, in: context).first)
        #expect(checkIn.date == day("2026-09-21"))
        #expect(checkIn.status == .scheduled)
        #expect(checkIn.purpose == "see the long multiplication laid out")
        #expect(checkIns(of: work, in: context).count == 1)
    }

    @Test("a closed day moves forward to the next open day and the reply says so")
    func moveToClosedDayLandsOnNextOpenDay() async throws {
        let (tools, context) = try makeTools()
        let service = SchoolCalendarService.shared
        service.invalidateCache()
        defer { service.invalidateCache() }
        let rows = try await assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])

        // 2026-09-19 is a Saturday.
        let receipt = try await tool(named: "update_work", in: tools).handler([
            "work_id": .string(try id(of: work)),
            "move_check_in_from": .string("2026-09-18"),
            "move_check_in_to": .string("2026-09-19")
        ])
        #expect(receipt.contains("moved the check-in from 2026-09-18 to 2026-09-21"))
        #expect(receipt.contains("2026-09-19 is not a school day, so it moved forward to 2026-09-21"))
        #expect(try #require(checkIns(of: work, in: context).first).date == day("2026-09-21"))
    }

    @Test("linked copies move together and a completed sibling stays")
    func moveCarriesSiblingsAndKeepsCompletedOnes() async throws {
        let (tools, context) = try makeTools()
        let rows = try await assignWithCheckIn(to: ["Maya", "Eli", "Ana"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])
        let eli = try #require(rows["Eli"])
        let ana = try #require(rows["Ana"])
        let update = try tool(named: "update_work", in: tools)

        // Ana was seen on the day; her check-in is done.
        _ = try await update.handler([
            "work_id": .string(try id(of: ana)),
            "complete_check_in_on": .string("2026-09-18")
        ])

        let receipt = try await update.handler([
            "work_id": .string(try id(of: maya)),
            "move_check_in_from": .string("2026-09-18"),
            "move_check_in_to": .string("2026-09-21")
        ])
        #expect(receipt.contains("moved the check-in from 2026-09-18 to 2026-09-21"))
        #expect(receipt.contains("also moved Eli Test's linked copy [work id=\(try id(of: eli))]"))
        #expect(receipt.contains("Ana Test's linked copy [work id=\(try id(of: ana))] stayed on 2026-09-18"))
        #expect(receipt.contains("already completed"))

        #expect(try #require(checkIns(of: maya, in: context).first).date == day("2026-09-21"))
        #expect(try #require(checkIns(of: eli, in: context).first).date == day("2026-09-21"))
        let anas = try #require(checkIns(of: ana, in: context).first)
        #expect(anas.date == day("2026-09-18"))
        #expect(anas.status == .completed)

        let schedule = try await tool(named: "schedule_for_range", in: tools).handler([
            "start_date": .string("2026-09-18"),
            "end_date": .string("2026-09-21")
        ])
        let old = section(for: "2026-09-18", in: schedule)
        let new = section(for: "2026-09-21", in: schedule)
        #expect(old.components(separatedBy: "Checkerboard practice").count - 1 == 1)
        #expect(old.contains("(completed)"))
        #expect(new.components(separatedBy: "Checkerboard practice").count - 1 == 2)
    }

    @Test("move_check_in_for_this_child_only leaves the siblings and says so")
    func moveThisChildOnlyLeavesSiblings() async throws {
        let (tools, context) = try makeTools()
        let rows = try await assignWithCheckIn(to: ["Maya", "Eli"], tools: tools, context: context)
        let maya = try #require(rows["Maya"])
        let eli = try #require(rows["Eli"])

        let receipt = try await tool(named: "update_work", in: tools).handler([
            "work_id": .string(try id(of: maya)),
            "move_check_in_from": .string("2026-09-18"),
            "move_check_in_to": .string("2026-09-21"),
            "move_check_in_for_this_child_only": .bool(true)
        ])
        #expect(receipt.contains("moved the check-in from 2026-09-18 to 2026-09-21"))
        #expect(receipt.contains("this child only — 1 linked copy still has its check-in on 2026-09-18"))
        #expect(try #require(checkIns(of: maya, in: context).first).date == day("2026-09-21"))
        #expect(try #require(checkIns(of: eli, in: context).first).date == day("2026-09-18"))
    }

    // MARK: - Refusals

    @Test("one move argument without the other names the missing one")
    func moveNeedsBothArguments() async throws {
        let (tools, context) = try makeTools()
        let rows = try await assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let workID = try id(of: try #require(rows["Maya"]))
        let update = try tool(named: "update_work", in: tools)

        let missingTo = await message {
            try await update.handler([
                "work_id": .string(workID),
                "move_check_in_from": .string("2026-09-18")
            ])
        }
        #expect(missingTo.contains("needs move_check_in_to"))

        let missingFrom = await message {
            try await update.handler([
                "work_id": .string(workID),
                "move_check_in_to": .string("2026-09-21")
            ])
        }
        #expect(missingFrom.contains("needs move_check_in_from"))
    }

    @Test("moving from a day with no check-in lists the days that have one")
    func moveFromMissingDayListsExistingDates() async throws {
        let (tools, context) = try makeTools()
        let rows = try await assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])

        let refusal = await message {
            try await tool(named: "update_work", in: tools).handler([
                "work_id": .string(try id(of: work)),
                "move_check_in_from": .string("2026-09-17"),
                "move_check_in_to": .string("2026-09-21")
            ])
        }
        #expect(refusal.contains("No check-in is scheduled on 2026-09-17"))
        #expect(refusal.contains("Its check-ins are on 2026-09-18"))
        #expect(try #require(checkIns(of: work, in: context).first).date == day("2026-09-18"))
    }

    @Test("a completed check-in cannot be moved")
    func moveRefusesCompletedCheckIn() async throws {
        let (tools, context) = try makeTools()
        let rows = try await assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])
        let update = try tool(named: "update_work", in: tools)

        _ = try await update.handler([
            "work_id": .string(try id(of: work)),
            "complete_check_in_on": .string("2026-09-18")
        ])
        let refusal = await message {
            try await update.handler([
                "work_id": .string(try id(of: work)),
                "move_check_in_from": .string("2026-09-18"),
                "move_check_in_to": .string("2026-09-21")
            ])
        }
        #expect(refusal.contains("already completed"))
        let checkIn = try #require(checkIns(of: work, in: context).first)
        #expect(checkIn.date == day("2026-09-18"))
        #expect(checkIn.status == .completed)
    }

    @Test("moving a check-in onto its own day is refused")
    func moveToSameDayIsRefused() async throws {
        let (tools, context) = try makeTools()
        let rows = try await assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])

        let refusal = await message {
            try await tool(named: "update_work", in: tools).handler([
                "work_id": .string(try id(of: work)),
                "move_check_in_from": .string("2026-09-18"),
                "move_check_in_to": .string("2026-09-18")
            ])
        }
        #expect(refusal.contains("already on 2026-09-18"))
    }

    // MARK: - Completing

    @Test("complete_check_in_on still completes the day's scheduled check-in")
    func completeCheckInStillWorks() async throws {
        let (tools, context) = try makeTools()
        let rows = try await assignWithCheckIn(to: ["Maya"], tools: tools, context: context)
        let work = try #require(rows["Maya"])

        let receipt = try await tool(named: "update_work", in: tools).handler([
            "work_id": .string(try id(of: work)),
            "complete_check_in_on": .string("2026-09-18")
        ])
        #expect(receipt.contains("completed the check-in on 2026-09-18"))
        #expect(try #require(checkIns(of: work, in: context).first).status == .completed)
    }
}
