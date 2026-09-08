import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("MCP Schedule Tools")
@MainActor
struct MCPScheduleToolsTests {
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

    private func assignments(in context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
    }

    // MARK: - schedule_presentation

    @Test("schedule_presentation plans a lesson and shows it on the day")
    func schedulePresentationPlansAndShows() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", area: "Math", sequence: "Decimal")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "schedule_presentation", in: tools).handler([
            "lesson": .string("Golden Beads"),
            "student_names": .array([.string("Maya")]),
            "date": .string("2026-09-14")
        ])
        #expect(receipt.contains("Scheduled"))
        #expect(receipt.contains("Golden Beads"))

        let planned = try #require(assignments(in: context).first)
        #expect(planned.state == .scheduled)
        #expect(planned.scheduledForDay == AppCalendar.startOfDay(try day("2026-09-14")))

        let schedule = try await tool(named: "schedule_for_range", in: tools).handler([
            "start_date": .string("2026-09-14")
        ])
        #expect(schedule.contains("Golden Beads"))
        #expect(schedule.contains("Maya Soto"))
    }

    @Test("schedule_presentation moves an existing plan instead of duplicating it")
    func schedulePresentationReusesExistingPlan() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains", area: "Math", sequence: "Skip Counting")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Ross")
        CoreDataTestHelpers.save(context)

        let scheduleTool = try tool(named: "schedule_presentation", in: tools)
        _ = try await scheduleTool.handler([
            "lesson": .string("Bead Chains"),
            "student_names": .array([.string("Eli")]),
            "date": .string("2026-09-14")
        ])
        let second = try await scheduleTool.handler([
            "lesson": .string("Bead Chains"),
            "student_names": .array([.string("Eli")]),
            "date": .string("2026-09-16")
        ])

        #expect(second.contains("Moved the existing plan"))
        #expect(assignments(in: context).count == 1)
        let planned = try #require(assignments(in: context).first)
        #expect(planned.scheduledForDay == AppCalendar.startOfDay(try day("2026-09-16")))
    }

    // MARK: - reschedule_presentation

    @Test("reschedule_presentation unschedules without deleting the plan")
    func reschedulePresentationUnschedules() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Operations")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "Perez")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "schedule_presentation", in: tools).handler([
            "lesson": .string("Stamp Game"),
            "student_names": .array([.string("Ana")]),
            "date": .string("2026-09-15")
        ])
        let planned = try #require(assignments(in: context).first)
        let id = try #require(planned.id).uuidString

        let receipt = try await tool(named: "reschedule_presentation", in: tools).handler([
            "presentation_id": .string(id),
            "unschedule": .bool(true)
        ])
        #expect(receipt.contains("planning list"))
        #expect(assignments(in: context).count == 1)
        #expect(planned.state == .draft)
    }

    @Test("reschedule_presentation refuses a presentation already given")
    func reschedulePresentationRefusesGivenLesson() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Test Tubes", area: "Math", sequence: "Division")
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        CoreDataTestHelpers.save(context)

        let assignment = PresentationFactory.makeDraft(
            lesson: lesson, students: [student], context: context
        )
        assignment.markPresented(at: Date())
        CoreDataTestHelpers.save(context)
        let id = try #require(assignment.id).uuidString

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "reschedule_presentation", in: tools).handler([
                "presentation_id": .string(id),
                "date": .string("2026-09-20")
            ])
        }
    }

    // MARK: - schedule_for_range

    @Test("schedule_for_range reports an empty span rather than inventing days")
    func scheduleForRangeReportsEmptySpan() async throws {
        let (tools, _) = try makeTools()
        let output = try await tool(named: "schedule_for_range", in: tools).handler([
            "start_date": .string("2026-10-05"),
            "end_date": .string("2026-10-09")
        ])
        #expect(output.contains("Nothing is scheduled"))
    }

    @Test("schedule_for_range rejects an end before its start")
    func scheduleForRangeRejectsBackwardsRange() async throws {
        let (tools, _) = try makeTools()
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "schedule_for_range", in: tools).handler([
                "start_date": .string("2026-10-09"),
                "end_date": .string("2026-10-05")
            ])
        }
    }
}
