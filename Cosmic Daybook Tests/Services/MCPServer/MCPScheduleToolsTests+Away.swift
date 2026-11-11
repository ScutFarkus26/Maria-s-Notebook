import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// schedule_presentation and reschedule_presentation name the children who
/// are with another teacher then (plan "Co-teacher times when scheduling",
/// decision 8), and never refuse for it.
extension MCPScheduleToolsTests {

    /// A notebook with Morah Devora taking Maya Soto 9:50–10:20 every Monday.
    private func awayNotebook() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", area: "Math", sequence: "Decimal")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let mayaID = try #require(maya.id)
        TimetableService.makeStarterLanes(in: context)
        let devora = TimetableService.addPerson(named: "Morah Devora", in: context)
        TimetableService.addBlock(
            TimetableBlockValues(
                startMinute: 9 * 60 + 50, lengthMinutes: 30, title: "Chumash", studentIDs: [mayaID.uuidString]
            ),
            to: devora, on: [.monday], in: context
        )
        CoreDataTestHelpers.save(context)
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func run(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> String {
        try await #require(tools.first { $0.name == name }).handler(arguments)
    }

    @Test("schedule_presentation names a child with another teacher during the set time, and still schedules")
    func scheduleNamesAChildAway() async throws {
        let (tools, context) = try awayNotebook()
        // Monday 14 September 2026.
        let receipt = try await run("schedule_presentation", [
            "lesson": .string("Golden Beads"), "student_names": .array([.string("Maya")]),
            "date": .string("2026-09-14"), "time": .string("10:00")
        ], in: tools)
        #expect(receipt.contains("Scheduled"))
        #expect(receipt.hasSuffix(" Maya S is with Morah Devora 9:50–10:20."))
        #expect(context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).count == 1)
    }

    @Test("schedule_presentation says nothing about a group the set time misses, or on another weekday")
    func scheduleQuietWhenClear() async throws {
        let (tools, _) = try awayNotebook()
        let clear = try await run("schedule_presentation", [
            "lesson": .string("Golden Beads"), "student_names": .array([.string("Maya")]),
            "date": .string("2026-09-14"), "time": .string("10:20")
        ], in: tools)
        #expect(!clear.contains("Morah Devora"))
        let tuesday = try await run("schedule_presentation", [
            "lesson": .string("Golden Beads"), "student_names": .array([.string("Maya")]),
            "date": .string("2026-09-15")
        ], in: tools)
        #expect(!tuesday.contains("Morah Devora"))
    }

    @Test("A plan with no time hears about a group in its half; reschedule says the same, and not on unschedule")
    func untimedAndRescheduled() async throws {
        let (tools, context) = try awayNotebook()
        let receipt = try await run("schedule_presentation", [
            "lesson": .string("Golden Beads"), "student_names": .array([.string("Maya")]),
            "date": .string("2026-09-14")
        ], in: tools)
        #expect(receipt.hasSuffix(" Maya S is away 9:50–10:20 that morning."))
        let id = try #require(context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).first?.id?.uuidString)

        let afternoon = try await run("reschedule_presentation", [
            "presentation_id": .string(id), "time": .string("13:30")
        ], in: tools)
        #expect(!afternoon.contains("Morah Devora"))
        let during = try await run("reschedule_presentation", [
            "presentation_id": .string(id), "time": .string("09:30")
        ], in: tools)
        #expect(during.hasSuffix(" Maya S is with Morah Devora 9:50–10:20."))
        let nextWeek = try await run("reschedule_presentation", [
            "presentation_id": .string(id), "date": .string("2026-09-21")
        ], in: tools)
        #expect(nextWeek.hasSuffix(" Maya S is with Morah Devora 9:50–10:20."), "the set time goes with it")
        let off = try await run("reschedule_presentation", [
            "presentation_id": .string(id), "unschedule": .bool(true)
        ], in: tools)
        #expect(!off.contains("Morah Devora"))
    }
}
