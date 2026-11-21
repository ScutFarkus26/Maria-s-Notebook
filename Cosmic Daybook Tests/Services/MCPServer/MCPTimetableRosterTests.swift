import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Claude's timetable writes name children from the class, the way the block
/// sheet does (`StudentNameMatcher` over the enrolled roster; plan "Domain
/// logic fixes", R7): a child who has left never stands in the way, nor is
/// added, and a name that only sounds like a child's is asked about.
@Suite("MCP Timetable Tools: children from the class")
@MainActor
struct MCPTimetableRosterTests {

    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        TimetableService.makeStarterLanes(in: context)
        TimetableService.addPerson(named: "Morah Devora", in: context)
        CoreDataTestHelpers.save(context)
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func setGroup(_ children: [String], in tools: [MCPToolDefinition]) async throws -> String {
        let tool = try #require(tools.first { $0.name == "set_timetable" })
        return try await tool.handler([
            "lane": "Morah Devora", "confirm": true,
            "blocks": [["weekdays": ["Monday"], "start": "10:00", "length_minutes": 30, "title": "Hebrew",
                        "children": .array(children.map { .string($0) })]]
        ])
    }

    private func groupChildren(in context: NSManagedObjectContext) -> [String] {
        let lane = TimetableService.lanes(in: context).first { $0.name == "Morah Devora" }
        return lane.map { TimetableService.blocks(of: $0, in: context) }?.first?.studentIDs ?? []
    }

    @Test("A first name shared with a child who has left means the child in the class")
    func departedNamesakeDoesNotStandInTheWay() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Maya", lastName: "Soto", enrollmentStatus: .withdrawn
        )
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Levy")
        CoreDataTestHelpers.save(context)

        _ = try await setGroup(["Maya"], in: tools)
        #expect(groupChildren(in: context) == [try #require(maya.id?.uuidString)])
    }

    @Test("A child who has left isn't added, and a name that only sounds alike is asked about")
    func departedAndSoundAlikeAreRefused() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Talia", lastName: "Gold", enrollmentStatus: .withdrawn
        )
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Leah", lastName: "Cohen")
        CoreDataTestHelpers.save(context)

        let left = await #expect(throws: MCPToolError.self) { _ = try await setGroup(["Talia"], in: tools) }
        #expect(left?.message.contains("has left") == true)
        let soundAlike = await #expect(throws: MCPToolError.self) { _ = try await setGroup(["Lea"], in: tools) }
        #expect(soundAlike?.message.contains("Leah C") == true)
        #expect(groupChildren(in: context).isEmpty)
    }
}
