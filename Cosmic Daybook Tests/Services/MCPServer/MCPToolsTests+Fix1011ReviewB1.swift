import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11, review (b) of the MCP write fixes: a huge count
// still crashed adjust_supply, and notes filed by record_presentation or
// unflagged by resolve_follow_up went unannounced. (The partial-save case,
// where finishing a track saved the first mark on its own, went with track
// enrollment on 2026-11-03: a mastery batch now saves once or not at all.)

@MainActor
private func call(
    _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
) async throws -> String {
    let tool = try #require(tools.first { $0.name == name })
    return try await tool.handler(arguments)
}

// MARK: - adjust_supply refuses a count too big to add up

// A separate suite: before the fix this one stops the test run (the sum
// overflows and the app traps).
@Suite("adjust_supply with huge numbers (Fix1011ReviewB1)")
@MainActor
struct SupplyHugeNumberFix1011ReviewB1Tests {
    private func seedPencils(in context: NSManagedObjectContext) -> CDSupply {
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = "Pencils"
        supply.currentQuantity = 40
        supply.createdAt = Date()
        #expect(CoreDataTestHelpers.save(context))
        return supply
    }

    @Test("A change or count far too big is refused, and the count is left alone")
    func hugeNumbersAreRefused() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        let pencils = seedPencils(in: context)

        for arguments: [String: JSONValue] in [
            ["supply": .string("Pencils"), "change": .int(Int.max)],
            ["supply": .string("Pencils"), "change": .int(Int.min)],
            ["supply": .string("Pencils"), "change": .int(5_000_000)],
            ["supply": .string("Pencils"), "set_to": .int(Int.min)],
            ["supply": .string("Pencils"), "set_to": .int(Int.max)],
            ["supply": .string("Pencils"), "set_to": .int(5_000_000)]
        ] {
            await #expect(throws: MCPToolError.self) {
                _ = try await call("adjust_supply", arguments, in: tools)
            }
        }
        #expect(pencils.currentQuantity == 40)
        #expect(!context.hasChanges)

        let ordinary = try await call(
            "adjust_supply", ["supply": .string("Pencils"), "change": .int(-12)], in: tools
        )
        #expect(ordinary.contains("now 28"))
    }
}

// MARK: - mark_mastered says what a partial save kept

// MARK: - Notes filed or unflagged over MCP are announced

@Suite("MCP note writes announce the note (Fix1011ReviewB1)")
@MainActor
struct NoteAnnouncementFix1011ReviewB1Tests {
    @Test("record_presentation announces the observations it filed")
    func recordPresentationAnnounces() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        CoreDataTestHelpers.seedLesson(in: context, name: "Racks and Tubes", area: "Math", sequence: "Division")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let announced = NoteDidSaveRecorder()
        defer { announced.stop() }

        _ = try await call("record_presentation", [
            "lesson": .string("Racks and Tubes"),
            "student_names": .array([.string("Ora")]),
            "group_observation": .string("Followed the exchange without prompting.")
        ], in: tools)

        let noteIDs = Set(context.safeFetch(CDFetchRequest(CDNote.self)).compactMap(\.id))
        #expect(noteIDs.count == 1)
        #expect(announced.ids.contains { noteIDs.contains($0) })
    }

    @Test("resolve_follow_up announces the note whose flag it cleared")
    func resolveFlagAnnounces() async throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let note = CDNote(context: context)
        note.body = "Lost the place when borrowing."
        note.scope = .student(try #require(ora.id))
        note.needsFollowUp = true
        let noteID = try #require(note.id)
        CoreDataTestHelpers.save(context)
        let announced = NoteDidSaveRecorder()
        defer { announced.stop() }

        _ = try await call("resolve_follow_up", ["id": .string(noteID.uuidString)], in: tools)

        #expect(!note.needsFollowUp)
        #expect(announced.ids.contains(noteID))
    }
}
