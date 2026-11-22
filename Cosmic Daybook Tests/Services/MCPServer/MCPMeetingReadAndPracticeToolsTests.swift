import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Meeting Read And Practice Tools")
@MainActor
struct MCPMeetingReadAndPracticeToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    // MARK: - student_meetings

    @Test("student_meetings reads back what create_meeting_entry filed")
    func studentMeetingsReadsBackWhatWasWritten() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "create_meeting_entry", in: tools).handler([
            "student": .string("Maya"),
            "reflection": .string("Proud of the map work."),
            "guide_notes": .string("Wants a partner for research.")
        ])

        let output = try await tool(named: "student_record", in: tools).presetting("sections", ["meetings"]).handler([
            "student_name": .string("Maya")
        ])
        #expect(output.contains("Meetings with Maya Soto"))
        #expect(output.contains("Proud of the map work."))
        #expect(output.contains("Wants a partner for research."))
    }

    @Test("student_meetings says so when there are none")
    func studentMeetingsReportsEmpty() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Ross")
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "student_record", in: tools).presetting("sections", ["meetings"]).handler([
            "student_name": .string("Eli")
        ])
        #expect(output.contains("No meetings are recorded"))
    }

    // MARK: - day_pad

    @Test("day_pad writes then reads the same day")
    func dayPadRoundTrips() async throws {
        let (tools, _) = try makeTools()
        let padTool = try tool(named: "day_pad", in: tools)

        let written = try await padTool.handler([
            "date": .string("2026-09-14"),
            "body": .string("Fire drill at 10. Library visit moved.")
        ])
        #expect(written.contains("Wrote the day pad"))

        let read = try await padTool.handler(["date": .string("2026-09-14")])
        #expect(read.contains("Fire drill at 10."))

        let empty = try await padTool.handler(["date": .string("2026-09-15")])
        #expect(empty.contains("is empty"))
    }
}
