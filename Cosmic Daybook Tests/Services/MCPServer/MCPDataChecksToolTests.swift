import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `data_checks`: lists history rows filed under another lesson than their
/// presentation, and birthdays before 1900, and changes nothing.
@Suite("MCP Data Checks")
@MainActor
struct MCPDataChecksToolTests {

    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func run(
        _ arguments: [String: JSONValue] = [:], in tools: [MCPToolDefinition]
    ) async throws -> String {
        let tool = try #require(tools.first { $0.name == "data_checks" })
        #expect(tool.annotations.readOnlyHint)
        return try await tool.handler(arguments)
    }

    private struct Seeded {
        let maya: CDStudent
        let leo: CDStudent
        let golden: CDLesson
        let stamp: CDLesson
        let presentation: CDLessonAssignment
        let misfiled: CDLessonPresentation
    }

    /// Maya's row still on Golden Beads while her presentation is on the
    /// Stamp Game; Leo, with a birthday in the year 15; Ora, fine.
    private func seed(in context: NSManagedObjectContext) throws -> Seeded {
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        let leo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leo", lastName: "Brown")
        let yearFifteen: Date = try #require(AppCalendar.shared.date(from: DateComponents(year: 15, month: 3, day: 5)))
        leo.birthday = yearFifteen
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        ora.birthday = try CoreDataTestHelpers.day("2016-04-02")
        let golden = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let stamp = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")

        let presentation = PresentationFactory.makeDraft(
            lessonID: try #require(stamp.id), studentIDs: [try #require(maya.id)], context: context
        )
        presentation.markPresented(at: try CoreDataTestHelpers.day("2026-09-14"))
        let misfiled = CDLessonPresentation(context: context)
        misfiled.studentID = try #require(maya.id).uuidString
        misfiled.lessonID = try #require(golden.id).uuidString
        misfiled.presentationID = try #require(presentation.id).uuidString
        misfiled.state = .presented

        // A row that agrees with its presentation is not listed.
        let ora1 = PresentationFactory.makeDraft(
            lessonID: try #require(golden.id), studentIDs: [try #require(ora.id)], context: context
        )
        ora1.markPresented(at: try CoreDataTestHelpers.day("2026-09-10"))
        let fine = CDLessonPresentation(context: context)
        fine.studentID = try #require(ora.id).uuidString
        fine.lessonID = try #require(golden.id).uuidString.lowercased()
        fine.presentationID = try #require(ora1.id).uuidString
        #expect(CoreDataTestHelpers.save(context))
        return Seeded(
            maya: maya, leo: leo, golden: golden, stamp: stamp, presentation: presentation, misfiled: misfiled
        )
    }

    @Test("Both checks list what they find, with citations, and nothing is changed")
    func listsBothAndChangesNothing() async throws {
        let (tools, context) = try makeTools()
        let seeded = try seed(in: context)

        let output = try await run(in: tools)

        #expect(output.contains("History rows on a different lesson than their presentation: 1."))
        #expect(output.contains("[student id=\(try #require(seeded.maya.id).uuidString)] Maya Stern"))
        #expect(output.contains("[historyRow id=\(try #require(seeded.misfiled.id).uuidString)]"))
        #expect(output.contains("[lesson id=\(try #require(seeded.golden.id).uuidString)] Golden Beads, but"))
        let presentationID = try #require(seeded.presentation.id).uuidString
        #expect(output.contains("[presentation id=\(presentationID)] (given 2026-09-14)"))
        #expect(output.contains("is [lesson id=\(try #require(seeded.stamp.id).uuidString)] Stamp Game"))
        #expect(!output.contains("Ora Levi"))

        #expect(output.contains("Birthdays before 1900: 1."))
        let leoID = try #require(seeded.leo.id).uuidString
        #expect(output.contains("[student id=\(leoID)] Leo Brown: birthday 0015-03-05"))

        #expect(!context.hasChanges)
        #expect(seeded.misfiled.lessonID == seeded.golden.id?.uuidString)
    }

    @Test("One check alone, and a clean notebook says none")
    func oneCheckAndNone() async throws {
        let (tools, context) = try makeTools()
        let clean = try await run(in: tools)
        #expect(clean.contains("History rows on a different lesson than their presentation: none."))
        #expect(clean.contains("Birthdays before 1900: none."))

        _ = try seed(in: context)
        let birthdaysOnly = try await run(["check": .string("early_birthdays")], in: tools)
        #expect(birthdaysOnly.contains("Birthdays before 1900: 1."))
        #expect(!birthdaysOnly.contains("History rows"))

        await #expect(throws: MCPToolError.self) {
            _ = try await run(["check": .string("everything")], in: tools)
        }
    }
}
