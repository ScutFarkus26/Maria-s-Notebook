import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Presentation History Tool")
@MainActor
struct MCPPresentationHistoryToolsTests {
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
    private func seedGiven(
        _ lesson: CDLesson, to student: CDStudent, on date: String, in context: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        let presentation = PresentationFactory.makeDraft(lesson: lesson, students: [student], context: context)
        presentation.markPresented(at: try day(date))
        return presentation
    }

    /// Ora: twelve dated presentations of Bells across 2026, one of the
    /// Stamp Game, and a checklist-only record of the Checkerboard.
    private struct Classroom {
        let ora: CDStudent
        let bells: CDLesson
        let stampGame: CDLesson
        let checkerboard: CDLesson
    }

    private func seedClassroom(in context: NSManagedObjectContext) throws -> Classroom {
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let bells = CoreDataTestHelpers.seedLesson(in: context, name: "Bells", area: "Music", sequence: "Tone Bars")
        let stampGame = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math")
        let checkerboard = CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math")
        for month in 1...12 {
            try seedGiven(bells, to: ora, on: String(format: "2026-%02d-10", month), in: context)
        }
        try seedGiven(stampGame, to: ora, on: "2026-03-01", in: context)
        let record = CDLessonPresentation(context: context)
        record.studentID = try #require(ora.id).uuidString
        record.lessonID = try #require(checkerboard.id).uuidString
        record.stateRaw = LessonPresentationState.proficient.rawValue
        record.presentedAt = try day("2025-05-04")
        record.masteredAt = try day("2025-06-20")
        #expect(CoreDataTestHelpers.save(context))
        return Classroom(ora: ora, bells: bells, stampGame: stampGame, checkerboard: checkerboard)
    }

    @Test("Ten newest by default, with the count held back said out loud; limit raises the cap")
    func defaultLimitAndRaisedLimit() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)
        let history = try tool(named: "student_presentation_history", in: tools)

        let capped = try await history.handler(["student_name": .string("Ora")])
        #expect(capped.contains(
            "Presentations for Ora Pardo (showing 10 of 13; raise limit or pass since for the rest):"
        ))
        #expect(capped.components(separatedBy: "[presentation id=").count - 1 == 10)
        #expect(capped.contains("2026-12-10 — Bells"))
        #expect(!capped.contains("2026-02-10"))

        let all = try await history.handler(["student_name": .string("Ora"), "limit": .int(200)])
        #expect(all.contains("Presentations for Ora Pardo (13):"))
        #expect(all.components(separatedBy: "[presentation id=").count - 1 == 13)
        #expect(all.contains("2026-01-10 — Bells"))
    }

    @Test("since keeps only presentations on or after the day")
    func sinceFilters() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)

        let recent = try await tool(named: "student_presentation_history", in: tools).handler([
            "student_name": .string("Ora"), "since": .string("2026-10-10")
        ])
        #expect(recent.contains("Presentations since 2026-10-10 for Ora Pardo (3):"))
        #expect(recent.contains("2026-10-10 — Bells"))
        #expect(!recent.contains("2026-09-10"))

        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "student_presentation_history", in: tools).handler([
                "student_name": .string("Ora"), "since": .string("October")
            ])
        }
        #expect(refusal?.message.contains("YYYY-MM-DD") == true)
    }

    @Test("a lesson given twice says which time it was, and why when the record says")
    func repeatRowsCarryTheirOrdinalAndPurpose() async throws {
        let (tools, context) = try makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let checkerboard = CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard", area: "Math")
        let stampGame = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math")
        try seedGiven(checkerboard, to: ora, on: "2026-03-11", in: context)
        let again = try seedGiven(checkerboard, to: ora, on: "2026-09-16", in: context)
        again.notes = "Second pass — planned 2026-09-16"
        try seedGiven(stampGame, to: ora, on: "2026-05-04", in: context)
        #expect(CoreDataTestHelpers.save(context))

        let history = try await tool(named: "student_presentation_history", in: tools).handler([
            "student_name": .string("Ora")
        ])
        #expect(history.contains("2026-09-16 — Checkerboard (2nd time; second pass) ("))
        // The first giving, and a lesson given once, say nothing.
        #expect(history.contains("2026-03-11 — Checkerboard ("))
        #expect(history.contains("2026-05-04 — Stamp Game ("))
        #expect(!history.contains("1st time"))

        // A revisit with no reason on the record still carries its ordinal.
        again.notes = ""
        #expect(CoreDataTestHelpers.save(context))
        let plain = try await tool(named: "student_presentation_history", in: tools).handler([
            "student_name": .string("Ora"), "lesson": .string("Checkerboard")
        ])
        #expect(plain.contains("2026-09-16 — Checkerboard (2nd time) ("))
    }

    @Test("lesson narrows to one lesson and reads the presentation record beside the dated rows")
    func lessonFilterAnswersHasSheHadIt() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let history = try tool(named: "student_presentation_history", in: tools)

        let stampGame = try await history.handler([
            "student_name": .string("Ora"), "lesson": .string("stamp game")
        ])
        #expect(stampGame.contains("Presentations of Stamp Game for Ora Pardo (1):"))
        #expect(stampGame.contains("2026-03-01 — Stamp Game"))
        #expect(!stampGame.contains("Bells"))
        #expect(stampGame.contains("No presentation record of Stamp Game for this child either."))

        // A checklist mark with no dated presentation is not "never had it".
        let byID = try #require(classroom.checkerboard.id).uuidString
        let checkerboard = try await history.handler([
            "student_name": .string("Ora"), "lesson": .string(byID)
        ])
        #expect(checkerboard.hasPrefix("No presentations of Checkerboard are recorded for Ora Pardo."))
        #expect(checkerboard.contains(
            "Presentation record of Checkerboard: mastered; presented 2025-05-04; mastered 2025-06-20."
        ))

        // Both filters together.
        let lateBells = try await history.handler([
            "student_name": .string("Ora"), "lesson": .string("Bells"), "since": .string("2026-11-01")
        ])
        #expect(lateBells.contains("Presentations of Bells, since 2026-11-01 for Ora Pardo (2):"))

        let unknown = await #expect(throws: MCPToolError.self) {
            _ = try await history.handler(["student_name": .string("Ora"), "lesson": .string("Astronomy")])
        }
        #expect(unknown?.message.contains("find_lessons") == true)
    }
}
