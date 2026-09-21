import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

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
        #expect(planned.scheduledForDay == AppCalendar.startOfDay(try CoreDataTestHelpers.day("2026-09-14")))

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
        #expect(planned.scheduledForDay == AppCalendar.startOfDay(try CoreDataTestHelpers.day("2026-09-16")))
    }

    @Test("schedule_presentation defaults to the morning half and honours an HH:MM time")
    func schedulePresentationTakesATime() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Katz")
        CoreDataTestHelpers.save(context)
        let schedule = try tool(named: "schedule_presentation", in: tools)

        let morning = try await schedule.handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Noa")]),
            "date": .string("2026-09-16")
        ])
        // A plan with no time is an order within a half, so the receipt names
        // the half rather than the 9 o'clock the ordering base happens to use.
        #expect(morning.contains("on 2026-09-16 in the morning."))
        let planned = try #require(assignments(in: context).first)
        #expect(MCPNotebookTools.timeString(planned.scheduledFor) == "09:00")

        // The same lesson and student moves the existing plan, now with a time.
        let timed = try await schedule.handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Noa")]),
            "date": .string("2026-09-17"),
            "time": .string("10:30")
        ])
        #expect(timed.contains("Moved the existing plan for"))
        #expect(timed.contains("on 2026-09-17 at 10:30."))
        #expect(assignments(in: context).count == 1)
        #expect(planned.scheduledForDay == AppCalendar.startOfDay(try CoreDataTestHelpers.day("2026-09-17")))
        #expect(MCPNotebookTools.timeString(planned.scheduledFor) == "10:30")

        let onTheDay = try await tool(named: "schedule_for_range", in: tools).handler([
            "start_date": .string("2026-09-17")
        ])
        #expect(onTheDay.contains("Checkerboard at 10:30"))
    }

    @Test("schedule_presentation rejects a malformed time without writing")
    func schedulePresentationRejectsBadTime() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Noa", lastName: "Katz")
        CoreDataTestHelpers.save(context)

        for bad in ["10:75", "25:00", "1030", "10:30 am", "ten"] {
            let refusal = await #expect(throws: MCPToolError.self) {
                _ = try await tool(named: "schedule_presentation", in: tools).handler([
                    "lesson": .string("Checkerboard"),
                    "student_names": .array([.string("Noa")]),
                    "date": .string("2026-09-16"),
                    "time": .string(bad)
                ])
            }
            #expect(refusal?.message.contains("HH:MM") == true, "\(bad)")
        }
        #expect(assignments(in: context).isEmpty)
    }

    // MARK: - reschedule_presentation

    @Test("reschedule_presentation moves a plan to a day and time, and a time alone keeps the day")
    func reschedulePresentationTakesATime() async throws {
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
        let reschedule = try tool(named: "reschedule_presentation", in: tools)

        let moved = try await reschedule.handler([
            "presentation_id": .string(id), "date": .string("2026-09-18"), "time": .string("13:15")
        ])
        #expect(moved.contains("now scheduled for 2026-09-18 at 13:15."))
        #expect(planned.scheduledForDay == AppCalendar.startOfDay(try CoreDataTestHelpers.day("2026-09-18")))
        #expect(MCPNotebookTools.timeString(planned.scheduledFor) == "13:15")

        let retimed = try await reschedule.handler([
            "presentation_id": .string(id), "time": .string("09:45")
        ])
        #expect(retimed.contains("stays on 2026-09-18, now at 09:45."))
        #expect(planned.scheduledForDay == AppCalendar.startOfDay(try CoreDataTestHelpers.day("2026-09-18")))
        #expect(MCPNotebookTools.timeString(planned.scheduledFor) == "09:45")

        // A bare date drops back into the morning half of the new day.
        let dated = try await reschedule.handler([
            "presentation_id": .string(id), "date": .string("2026-09-21")
        ])
        #expect(dated.contains("now scheduled for 2026-09-21 in the morning."))

        // Off the calendar, a time has no day to go with.
        _ = try await reschedule.handler(["presentation_id": .string(id), "unschedule": .bool(true)])
        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await reschedule.handler(["presentation_id": .string(id), "time": .string("10:00")])
        }
        #expect(refusal?.message.contains("Pass a date as well") == true)
    }

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

    @Test("schedule_for_range says which half of the day, and never invents 09:00")
    func scheduleForRangeReportsTheHalf() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Bank Game", area: "Math", sequence: "Operations")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Rivka", lastName: "Stern")
        CoreDataTestHelpers.save(context)
        let schedule = try tool(named: "schedule_presentation", in: tools)
        let range = try tool(named: "schedule_for_range", in: tools)

        // 79ff3714 made an unscheduled-time plan an *ordering* slot: hour 9,
        // minute 0, and the rank in the seconds. Read as a clock, every row in
        // the live notebook came back "at 09:00" — a time nobody had set.
        let receipt = try await schedule.handler([
            "lesson": .string("Bank Game"),
            "student_names": .array([.string("Rivka")]),
            "date": .string("2026-09-15")
        ])
        #expect(receipt.contains("in the morning"))
        #expect(!receipt.contains("09:00"))

        let listing = try await range.handler(["start_date": .string("2026-09-15")])
        #expect(listing.contains("Bank Game in the morning"))
        #expect(!listing.contains("09:00"))

        // A time the guide actually set still reads as that time.
        _ = try await schedule.handler([
            "lesson": .string("Bank Game"),
            "student_names": .array([.string("Rivka")]),
            "date": .string("2026-09-15"),
            "time": .string("10:30")
        ])
        let timed = try await range.handler(["start_date": .string("2026-09-15")])
        #expect(timed.contains("Bank Game at 10:30"))
    }

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
