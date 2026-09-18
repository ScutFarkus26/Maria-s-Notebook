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

        let output = try await tool(named: "student_meetings", in: tools).handler([
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

        let output = try await tool(named: "student_meetings", in: tools).handler([
            "student_name": .string("Eli")
        ])
        #expect(output.contains("No meetings are recorded"))
    }

    // MARK: - practice_sessions

    @Test("practice_sessions reports the behaviours the guide flagged")
    func practiceSessionsReportsBehaviours() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "Perez")
        CoreDataTestHelpers.save(context)
        let studentID = try #require(student.id)

        let session = CDPracticeSession(context: context)
        session.id = UUID()
        session.date = Date()
        session.studentIDsArray = [studentID.uuidString]
        session.madeBreakthrough = true
        session.helpedPeer = true
        session.sharedNotes = "Finally saw the pattern in the bead chain."
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "practice_sessions", in: tools).handler([
            "student_name": .string("Ana")
        ])
        #expect(output.contains("Ana Perez"))
        #expect(output.contains("Finally saw the pattern in the bead chain."))
        #expect(output.contains("Noticed:"))
    }

    @Test("practice_sessions filters to one signal")
    func practiceSessionsFiltersBySignal() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        CoreDataTestHelpers.save(context)
        let key = try #require(student.id).uuidString

        let breakthrough = CDPracticeSession(context: context)
        breakthrough.id = UUID()
        breakthrough.date = Date()
        breakthrough.studentIDsArray = [key]
        breakthrough.madeBreakthrough = true
        breakthrough.sharedNotes = "Breakthrough session"

        let ordinary = CDPracticeSession(context: context)
        ordinary.id = UUID()
        ordinary.date = Date()
        ordinary.studentIDsArray = [key]
        ordinary.sharedNotes = "Ordinary session"
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "practice_sessions", in: tools).handler([
            "student_name": .string("Sam"),
            "signal": .string("madeBreakthrough")
        ])
        #expect(output.contains("Breakthrough session"))
        #expect(!output.contains("Ordinary session"))
    }

    // MARK: - recall_checks

    @Test("recall_checks names the lesson and its outcome")
    func recallChecksNameLessonAndOutcome() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Rae", lastName: "Kim")
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Chains", area: "Math", sequence: "Skip Counting"
        )
        CoreDataTestHelpers.save(context)

        let check = CDLessonRecallCheck(context: context)
        check.id = UUID()
        check.studentID = try #require(student.id).uuidString
        check.lessonID = try #require(lesson.id).uuidString
        check.outcome = .shaky
        check.checkedAt = Date()
        check.note = "Needed a reminder of the pattern."
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "recall_checks", in: tools).handler([
            "student_name": .string("Rae")
        ])
        #expect(output.contains("Bead Chains"))
        #expect(output.contains("shaky"))
        #expect(output.contains("Needed a reminder of the pattern."))
    }

    @Test("recall_checks filters by outcome")
    func recallChecksFilterByOutcome() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ivy", lastName: "Chen")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        CoreDataTestHelpers.save(context)
        let studentKey = try #require(student.id).uuidString
        let lessonKey = try #require(lesson.id).uuidString

        for outcome in [RecallOutcome.retained, .forgotten] {
            let check = CDLessonRecallCheck(context: context)
            check.id = UUID()
            check.studentID = studentKey
            check.lessonID = lessonKey
            check.outcome = outcome
            check.checkedAt = Date()
        }
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "recall_checks", in: tools).handler([
            "student_name": .string("Ivy"),
            "outcome": .string("forgotten")
        ])
        #expect(output.contains("1 recall check"))
        #expect(output.contains("forgotten"))
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
