import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// The enrollment guard on `schedule_presentation` and
/// `update_presentation_roster`: a child who has left the classroom cannot be
/// put on a lesson, and the refusal says nothing was changed.
@Suite("MCP Enrollment Guard")
@MainActor
struct MCPEnrollmentGuardToolsTests {
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

    /// Naomi left in June, Rivka transferred without a recorded day, Etty is here.
    private struct Roster {
        let lesson: CDLesson
        let naomi: CDStudent
        let rivka: CDStudent
        let etty: CDStudent
    }

    private func seedRoster(in context: NSManagedObjectContext) throws -> Roster {
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let naomi = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Naomi", lastName: "Levin",
            enrollmentStatus: .withdrawn, dateWithdrawn: try day("2026-06-12")
        )
        let rivka = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rivka", lastName: "Stein", enrollmentStatus: .transferred
        )
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        #expect(CoreDataTestHelpers.save(context))
        return Roster(lesson: lesson, naomi: naomi, rivka: rivka, etty: etty)
    }

    // MARK: - schedule_presentation

    @Test("schedule_presentation refuses a withdrawn child and schedules nothing")
    func schedulePresentationRefusesAWithdrawnChild() async throws {
        let (tools, context) = try makeTools()
        _ = try seedRoster(in: context)

        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "schedule_presentation", in: tools).handler([
                "lesson": .string("Checkerboard"),
                "student_names": .array([.string("Naomi"), .string("Etty")]),
                "date": .string("2026-09-16")
            ])
        }
        let message = try #require(refusal?.message)
        #expect(message.hasPrefix("schedule_presentation refused — nothing has been changed."))
        #expect(message.contains(
            "Naomi Levin is withdrawn (departed 2026-06-12) and cannot be scheduled for a presentation."
        ))
        #expect(message.contains("list_students shows the current roster."))
        #expect(assignments(in: context).isEmpty)
    }

    @Test("a transferred child is refused too, and two of them are listed together")
    func schedulePresentationRefusesATransferredChild() async throws {
        let (tools, context) = try makeTools()
        _ = try seedRoster(in: context)

        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "schedule_presentation", in: tools).handler([
                "lesson": .string("Checkerboard"),
                "student_names": .array([.string("Rivka")]),
                "date": .string("2026-09-16")
            ])
        }
        #expect(try #require(refusal?.message).contains(
            "Rivka Stein is transferred and cannot be scheduled for a presentation."
        ))

        let both = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "schedule_presentation", in: tools).handler([
                "lesson": .string("Checkerboard"),
                "student_names": .array([.string("Naomi"), .string("Rivka"), .string("Etty")]),
                "date": .string("2026-09-16")
            ])
        }
        #expect(try #require(both?.message).contains(
            "2 of these children have left the classroom and cannot be scheduled for a "
                + "presentation: Naomi Levin (withdrawn, departed 2026-06-12), Rivka Stein (transferred)."
        ))
        #expect(assignments(in: context).isEmpty)
    }

    @Test("an all-enrolled group is scheduled as before")
    func schedulePresentationAllowsEnrolledChildren() async throws {
        let (tools, context) = try makeTools()
        _ = try seedRoster(in: context)

        let receipt = try await tool(named: "schedule_presentation", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Etty")]),
            "date": .string("2026-09-16")
        ])
        #expect(receipt.contains("Scheduled"))
        #expect(assignments(in: context).count == 1)
    }

    // MARK: - update_presentation_roster

    @Test("update_presentation_roster refuses to add a child who has left, and changes nothing")
    func rosterRefusesAddingAFormerStudent() async throws {
        let (tools, context) = try makeTools()
        let roster = try seedRoster(in: context)
        let planned = PresentationFactory.makeScheduled(
            lesson: roster.lesson, students: [roster.etty],
            scheduledFor: try day("2026-09-16"), context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        let before = planned.studentIDs

        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_presentation_roster", in: tools).handler([
                "presentation_id": .string(try #require(planned.id).uuidString),
                "add_students": .array([.string("Naomi")])
            ])
        }
        let message = try #require(refusal?.message)
        #expect(message.hasPrefix("update_presentation_roster refused — nothing has been changed."))
        #expect(message.contains(
            "Naomi Levin is withdrawn (departed 2026-06-12) and cannot be added to a presentation's group."
        ))
        #expect(planned.studentIDs == before)
    }

    @Test("update_presentation_roster still takes a departed child off — that is the cleanup")
    func rosterAllowsRemovingAFormerStudent() async throws {
        let (tools, context) = try makeTools()
        let roster = try seedRoster(in: context)
        let planned = PresentationFactory.makeScheduled(
            lesson: roster.lesson, students: [roster.etty, roster.naomi],
            scheduledFor: try day("2026-09-16"), context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let receipt = try await tool(named: "update_presentation_roster", in: tools).handler([
            "presentation_id": .string(try #require(planned.id).uuidString),
            "remove_students": .array([.string("Naomi")])
        ])
        #expect(receipt.contains("removed Naomi Levin"))
        #expect(planned.studentIDs == [try #require(roster.etty.id).uuidString])
    }
}
