import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Year Plan Tools")
@MainActor
struct MCPYearPlanToolsTests {

    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    @discardableResult
    private func seedEntry(
        in context: NSManagedObjectContext,
        student: CDStudent,
        lesson: CDLesson,
        plannedDate: Date?,
        status: YearPlanEntryStatus = .planned,
        sequenceGroupKey: String = "Math::Counting"
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = student.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = plannedDate
        entry.sequenceGroupKey = sequenceGroupKey
        entry.statusRaw = status.rawValue
        return entry
    }

    // MARK: - update_year_plan_entry

    @Test("update_year_plan_entry changes one entry's status and returns it")
    func updateChangesStatus() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")
        let entry = seedEntry(
            in: context, student: maya, lesson: lesson, plannedDate: try day("2026-06-19")
        )
        CoreDataTestHelpers.save(context)
        let entryID = try #require(entry.id).uuidString

        let receipt = try await tool(named: "update_year_plan_entry", in: tools).handler([
            "entry_id": .string(entryID),
            "status": .string("skipped")
        ])

        #expect(receipt.contains("[yearPlanEntry id=\(entryID)]"))
        #expect(receipt.contains("The Rhombus"))
        #expect(receipt.contains("skipped"))
        #expect(entry.status == .skipped)
        // Skipped, never deleted — the row is still there to come back to.
        #expect(context.safeFetch(CDFetchRequest(CDYearPlanEntry.self)).count == 1)
    }

    @Test("update_year_plan_entry moves a target date")
    func updateMovesTargetDate() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Trapezoid")
        let entry = seedEntry(
            in: context, student: maya, lesson: lesson, plannedDate: try day("2026-06-24")
        )
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "update_year_plan_entry", in: tools).handler([
            "entry_id": .string(try #require(entry.id).uuidString),
            "target_date": .string("2026-10-05")
        ])

        let moved = AppCalendar.startOfDay(try day("2026-10-05"))
        #expect(receipt.contains("The Trapezoid"))
        #expect(entry.plannedDate == moved)
        // Still planned: only the date was asked for.
        #expect(entry.status == .planned)
    }

    @Test("update_year_plan_entry puts a skipped entry back to planned")
    func updateRestoresSkippedEntry() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Decagon")
        let entry = seedEntry(
            in: context, student: maya, lesson: lesson,
            plannedDate: try day("2026-06-29"), status: .skipped
        )
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "update_year_plan_entry", in: tools).handler([
            "entry_id": .string(try #require(entry.id).uuidString),
            "status": .string("planned")
        ])

        #expect(entry.status == .planned)
    }

    @Test("update_year_plan_entry refuses an entry already promoted onto the calendar")
    func updateRefusesPromotedEntry() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Introduction to Angles")
        let entry = seedEntry(
            in: context, student: maya, lesson: lesson,
            plannedDate: try day("2026-05-22"), status: .promoted
        )
        let assignmentID = UUID().uuidString
        entry.promotedAssignmentID = assignmentID
        CoreDataTestHelpers.save(context)
        let originalTarget = try day("2026-05-22")

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_year_plan_entry", in: tools).handler([
                "entry_id": .string(try #require(entry.id).uuidString),
                "status": .string("skipped")
            ])
        }

        // Untouched, and still pointing at its assignment.
        #expect(entry.status == .promoted)
        #expect(entry.promotedAssignmentID == assignmentID)
        #expect(entry.plannedDate == originalTarget)
    }

    @Test("update_year_plan_entry refuses promoted as a status to set by hand")
    func updateRefusesPromotingByHand() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Parts of an Angle")
        let entry = seedEntry(
            in: context, student: maya, lesson: lesson, plannedDate: try day("2026-06-04")
        )
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_year_plan_entry", in: tools).handler([
                "entry_id": .string(try #require(entry.id).uuidString),
                "status": .string("promoted")
            ])
        }
        // A promoted entry with no assignment behind it would be a lie.
        #expect(entry.status == .planned)
        #expect(entry.promotedAssignmentID == nil)
    }

    @Test("update_year_plan_entry rejects an unknown entry_id")
    func updateRejectsUnknownID() async throws {
        let (tools, _) = try makeTools()
        let missing = UUID().uuidString

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_year_plan_entry", in: tools).handler([
                "entry_id": .string(missing),
                "status": .string("skipped")
            ])
        }
    }

    @Test("update_year_plan_entry rejects an entry_id that is not a uuid")
    func updateRejectsMalformedID() async throws {
        let (tools, _) = try makeTools()

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_year_plan_entry", in: tools).handler([
                "entry_id": .string("the rhombus one")
            ])
        }
    }

    @Test("update_year_plan_entry refuses a call that asks for no change")
    func updateRefusesEmptyChange() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Bisecting an Angle")
        let entry = seedEntry(
            in: context, student: maya, lesson: lesson, plannedDate: try day("2026-06-22")
        )
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_year_plan_entry", in: tools).handler([
                "entry_id": .string(try #require(entry.id).uuidString)
            ])
        }
    }

    // MARK: - skip_year_plan_entries

    @Test("skip_year_plan_entries skips every planned entry for one student and leaves the rest")
    func bulkSkipForOneStudent() async throws {
        let (tools, context) = try makeTools()
        let maytal = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maytal", lastName: "Meyer")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let angles = CoreDataTestHelpers.seedLesson(in: context, name: "Introduction to Angles")
        let rhombus = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")

        // Two of Maytal's targets fell in the school year that has ended, one
        // is still ahead, one is promoted. The receipt names the first two as
        // carried over — last year's intentions, not debt she is behind on.
        let behindOne = seedEntry(
            in: context, student: maytal, lesson: angles, plannedDate: try day("2026-05-22")
        )
        let behindTwo = seedEntry(
            in: context, student: maytal, lesson: rhombus, plannedDate: try day("2026-06-19")
        )
        let ahead = seedEntry(
            in: context, student: maytal, lesson: rhombus,
            plannedDate: Date().addingTimeInterval(60 * 86_400)
        )
        let promoted = seedEntry(
            in: context, student: maytal, lesson: angles,
            plannedDate: try day("2026-05-01"), status: .promoted
        )
        // Another child's plan must not move.
        let orasEntry = seedEntry(
            in: context, student: ora, lesson: angles, plannedDate: try day("2026-05-22")
        )
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "skip_year_plan_entries", in: tools).handler([
            "student_name": .string("Maytal")
        ])

        #expect(receipt.contains("Skipped 3"))
        #expect(receipt.contains("Maytal Meyer"))
        #expect(receipt.contains("2 of them are carried over from last year."))
        #expect(!receipt.contains("behind pace"))
        #expect(behindOne.status == .skipped)
        #expect(behindTwo.status == .skipped)
        #expect(ahead.status == .skipped)
        // Promoted entries are on the calendar; this tool does not touch them.
        #expect(promoted.status == .promoted)
        #expect(orasEntry.status == .planned)
        // Nothing deleted.
        #expect(context.safeFetch(CDFetchRequest(CDYearPlanEntry.self)).count == 5)
    }

    @Test("skipped entries stay readable through year_plan and can be restored")
    func skippedEntriesRemainReadable() async throws {
        let (tools, context) = try makeTools()
        let maytal = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maytal", lastName: "Meyer")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Decagon")
        let entry = seedEntry(
            in: context, student: maytal, lesson: lesson, plannedDate: try day("2026-06-29")
        )
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "skip_year_plan_entries", in: tools).handler([
            "student_name": .string("Maytal")
        ])

        let skipped = try await tool(named: "year_plan", in: tools).handler([
            "student_name": .string("Maytal"),
            "status": .string("skipped")
        ])
        #expect(skipped.contains("The Decagon"))

        let planned = try await tool(named: "year_plan", in: tools).handler([
            "student_name": .string("Maytal"),
            "status": .string("planned")
        ])
        #expect(planned.contains("no planned year-plan entries"))

        // And back again, so a girl who re-enrols keeps her plan.
        _ = try await tool(named: "update_year_plan_entry", in: tools).handler([
            "entry_id": .string(try #require(entry.id).uuidString),
            "status": .string("planned")
        ])
        #expect(entry.status == .planned)
    }

    @Test("skip_year_plan_entries says so when there is nothing to skip")
    func bulkSkipWithNothingPlanned() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maytal", lastName: "Meyer")
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "skip_year_plan_entries", in: tools).handler([
            "student_name": .string("Maytal")
        ])
        #expect(receipt.contains("no planned year-plan entries"))
    }
}
