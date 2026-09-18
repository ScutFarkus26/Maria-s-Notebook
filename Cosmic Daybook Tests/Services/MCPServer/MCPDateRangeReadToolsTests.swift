import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Shared fixtures for the two date-range suites below.
@MainActor
private enum DateRange {
    static func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    static func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    static func daysAgo(_ days: Int) -> Date {
        AppCalendar.shared.date(byAdding: .day, value: -days, to: Date()) ?? Date()
    }

    /// The YYYY-MM-DD argument for a day that many days back.
    static func dayText(_ days: Int) -> JSONValue {
        .string(MCPNotebookTools.isoDay.string(from: daysAgo(days)))
    }

    @discardableResult
    static func seedNote(
        _ body: String, about student: CDStudent, daysOld: Int, in context: NSManagedObjectContext
    ) throws -> CDNote {
        let note = CoreDataTestHelpers.seedNote(in: context, body: body)
        note.createdAt = daysAgo(daysOld)
        note.scope = .student(try #require(student.id))
        return note
    }

    static func seedMeeting(
        _ focus: String, for student: CDStudent, daysOld: Int, in context: NSManagedObjectContext
    ) throws {
        let meeting = CDStudentMeeting(context: context)
        meeting.id = UUID()
        meeting.studentID = try #require(student.id).uuidString
        meeting.date = daysAgo(daysOld)
        meeting.focus = focus
        meeting.completed = true
    }

    static func seedPractice(
        _ notes: String, for student: CDStudent, daysOld: Int, in context: NSManagedObjectContext
    ) throws {
        let session = CDPracticeSession(context: context)
        session.id = UUID()
        session.date = daysAgo(daysOld)
        session.studentIDsArray = [try #require(student.id).uuidString]
        session.sharedNotes = notes
    }

    /// The lesson carries the context, so the seeder stays inside SwiftLint's
    /// parameter budget.
    static func seedRecall(
        _ outcome: RecallOutcome, for student: CDStudent, of lesson: CDLesson,
        daysOld: Int, note: String
    ) throws {
        let context = try #require(lesson.managedObjectContext)
        let check = CDLessonRecallCheck(context: context)
        check.id = UUID()
        check.studentID = try #require(student.id).uuidString
        check.lessonID = try #require(lesson.id).uuidString
        check.outcome = outcome
        check.checkedAt = daysAgo(daysOld)
        check.note = note
    }
}

/// `since` / `until` on the observation reads. The point of the arguments is
/// reach: a rolling `days_back` window stops at four months, so anything older
/// than that used to be unreachable over MCP no matter how the caller phrased
/// the question.
@Suite("MCP Date Range Observation Reads")
@MainActor
struct MCPDateRangeReadToolsTests {
    private func seedObservedStudent(in context: NSManagedObjectContext) throws -> CDStudent {
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.save(context)
        try DateRange.seedNote("Bead chain, two hundred days back.", about: ora, daysOld: 200, in: context)
        try DateRange.seedNote("Map work, this week.", about: ora, daysOld: 3, in: context)
        CoreDataTestHelpers.save(context)
        return ora
    }

    @Test("student_observations: the old arguments still read the last thirty days and nothing else")
    func observationsDefaultUnchanged() async throws {
        let (tools, context) = try DateRange.makeTools()
        try seedObservedStudent(in: context)

        let output = try await DateRange.tool(named: "student_observations", in: tools).handler([
            "student_name": .string("Ora")
        ])
        #expect(output.contains("Notes about Ora (last 30 days):"))
        #expect(output.contains("Map work, this week."))
        #expect(!output.contains("two hundred days back"))
    }

    @Test("student_observations: since reaches a note days_back could never see")
    func observationsSinceReachesOldNote() async throws {
        let (tools, context) = try DateRange.makeTools()
        try seedObservedStudent(in: context)

        let output = try await DateRange.tool(named: "student_observations", in: tools).handler([
            "student_name": .string("Ora"),
            "since": DateRange.dayText(365)
        ])
        #expect(output.contains("two hundred days back"))
        #expect(output.contains("Map work, this week."))
        #expect(output.contains("since "))
    }

    @Test("student_observations: until keeps the newer notes out")
    func observationsUntilExcludesNewer() async throws {
        let (tools, context) = try DateRange.makeTools()
        try seedObservedStudent(in: context)

        let output = try await DateRange.tool(named: "student_observations", in: tools).handler([
            "student_name": .string("Ora"),
            "since": DateRange.dayText(365),
            "until": DateRange.dayText(100)
        ])
        #expect(output.contains("two hundred days back"))
        #expect(!output.contains("Map work, this week."))
    }

    @Test("student_observations: a backwards window is an error, not an empty answer")
    func observationsRefusesBackwardsWindow() async throws {
        let (tools, context) = try DateRange.makeTools()
        try seedObservedStudent(in: context)

        await #expect(throws: MCPToolError.self) {
            _ = try await DateRange.tool(named: "student_observations", in: tools).handler([
                "student_name": .string("Ora"),
                "since": DateRange.dayText(10),
                "until": DateRange.dayText(200)
            ])
        }
    }

    @Test("student_observations: an unparseable date names the argument")
    func observationsRefusesMalformedDate() async throws {
        let (tools, context) = try DateRange.makeTools()
        try seedObservedStudent(in: context)

        do {
            _ = try await DateRange.tool(named: "student_observations", in: tools).handler([
                "student_name": .string("Ora"),
                "until": .string("last Tuesday")
            ])
            Issue.record("Expected a malformed-date error")
        } catch let error as MCPToolError {
            #expect(error.message.contains("until"))
            #expect(error.message.contains("YYYY-MM-DD"))
        }
    }

    @Test("student_observations: a truncated read says how many it held back")
    func observationsReportsHeldBackCount() async throws {
        let (tools, context) = try DateRange.makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.save(context)
        for index in 1...6 {
            try DateRange.seedNote("Note number \(index).", about: ora, daysOld: index, in: context)
        }
        CoreDataTestHelpers.save(context)

        let output = try await DateRange.tool(named: "student_observations", in: tools).handler([
            "student_name": .string("Ora"),
            "limit": .int(2)
        ])
        #expect(output.contains("showing 2 of 6"))
        #expect(output.contains("raise limit or pass since/until"))
    }

    @Test("presentations_missing_observations: since reaches a presentation outside days_back")
    func coverageSinceReachesOldPresentation() async throws {
        let (tools, context) = try DateRange.makeTools()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let bells = CoreDataTestHelpers.seedLesson(in: context, name: "Bells", area: "Music")
        CoreDataTestHelpers.save(context)
        let given = PresentationFactory.makeDraft(lesson: bells, students: [ora], context: context)
        given.markPresented(at: DateRange.daysAgo(200))
        CoreDataTestHelpers.save(context)
        let toolDefinition = try DateRange.tool(named: "presentations_missing_observations", in: tools)

        let defaultOutput = try await toolDefinition.handler([:])
        #expect(defaultOutput.contains("in the last 30 days has a linked observation"))

        let widened = try await toolDefinition.handler(["since": DateRange.dayText(365)])
        #expect(widened.contains("Bells"))
        #expect(widened.contains("Ora Pardo"))

        let capped = try await toolDefinition.handler([
            "since": DateRange.dayText(365), "until": DateRange.dayText(300)
        ])
        #expect(!capped.contains("Bells"))
    }
}

/// The same arguments on the meeting, practice and recall histories, whose
/// ceilings were a 20-meeting cap and a one-year `days_back`.
@Suite("MCP Date Range History Reads")
@MainActor
struct MCPDateRangeHistoryToolsTests {
    private func seedMetStudent(in context: NSManagedObjectContext) throws -> CDStudent {
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)
        try DateRange.seedMeeting("Sitting from last year.", for: maya, daysOld: 400, in: context)
        try DateRange.seedMeeting("Sitting from this week.", for: maya, daysOld: 2, in: context)
        CoreDataTestHelpers.save(context)
        return maya
    }

    @Test("student_meetings: the old arguments still read the whole history")
    func meetingsDefaultUnchanged() async throws {
        let (tools, context) = try DateRange.makeTools()
        try seedMetStudent(in: context)

        let output = try await DateRange.tool(named: "student_meetings", in: tools).handler([
            "student_name": .string("Maya")
        ])
        #expect(output.contains("Meetings with Maya Soto:"))
        #expect(output.contains("Sitting from last year."))
        #expect(output.contains("Sitting from this week."))
    }

    @Test("student_meetings: since and until narrow the history to one stretch")
    func meetingsWindowNarrows() async throws {
        let (tools, context) = try DateRange.makeTools()
        try seedMetStudent(in: context)
        let toolDefinition = try DateRange.tool(named: "student_meetings", in: tools)

        let recent = try await toolDefinition.handler([
            "student_name": .string("Maya"), "since": DateRange.dayText(30)
        ])
        #expect(recent.contains("Sitting from this week."))
        #expect(!recent.contains("Sitting from last year."))

        let older = try await toolDefinition.handler([
            "student_name": .string("Maya"), "until": DateRange.dayText(100)
        ])
        #expect(older.contains("Sitting from last year."))
        #expect(!older.contains("Sitting from this week."))

        await #expect(throws: MCPToolError.self) {
            _ = try await toolDefinition.handler([
                "student_name": .string("Maya"),
                "since": DateRange.dayText(2), "until": DateRange.dayText(400)
            ])
        }
    }

    @Test("student_meetings: the limit ceiling reaches past twenty")
    func meetingsLimitCeilingRaised() async throws {
        let (tools, context) = try DateRange.makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)
        for index in 1...24 {
            try DateRange.seedMeeting("Sitting \(index).", for: maya, daysOld: index, in: context)
        }
        CoreDataTestHelpers.save(context)

        let output = try await DateRange.tool(named: "student_meetings", in: tools).handler([
            "student_name": .string("Maya"), "limit": .int(30)
        ])
        #expect(output.contains("Sitting 24."))
        #expect(!output.contains("not shown"))
    }

    @Test("practice_sessions: since reaches past the year days_back stops at")
    func practiceSinceReachesBeyondAYear() async throws {
        let (tools, context) = try DateRange.makeTools()
        let ana = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "Perez")
        CoreDataTestHelpers.save(context)
        try DateRange.seedPractice("Bead frame, two years back.", for: ana, daysOld: 700, in: context)
        try DateRange.seedPractice("Bead frame, yesterday.", for: ana, daysOld: 1, in: context)
        CoreDataTestHelpers.save(context)
        let toolDefinition = try DateRange.tool(named: "practice_sessions", in: tools)

        let byDefault = try await toolDefinition.handler(["student_name": .string("Ana")])
        #expect(byDefault.contains("Bead frame, yesterday."))
        #expect(!byDefault.contains("two years back"))

        let widened = try await toolDefinition.handler([
            "student_name": .string("Ana"), "since": DateRange.dayText(1000)
        ])
        #expect(widened.contains("two years back"))

        let capped = try await toolDefinition.handler([
            "student_name": .string("Ana"),
            "since": DateRange.dayText(1000), "until": DateRange.dayText(600)
        ])
        #expect(capped.contains("two years back"))
        #expect(!capped.contains("yesterday"))

        await #expect(throws: MCPToolError.self) {
            _ = try await toolDefinition.handler([
                "student_name": .string("Ana"),
                "since": DateRange.dayText(1), "until": DateRange.dayText(700)
            ])
        }
    }

    @Test("recall_checks: since and until move the window off the rolling ninety days")
    func recallWindowMoves() async throws {
        let (tools, context) = try DateRange.makeTools()
        let rae = CoreDataTestHelpers.seedStudent(in: context, firstName: "Rae", lastName: "Kim")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Chains", area: "Math")
        CoreDataTestHelpers.save(context)
        try DateRange.seedRecall(.forgotten, for: rae, of: lesson, daysOld: 700,
                                 note: "Lost it two years back.")
        try DateRange.seedRecall(.retained, for: rae, of: lesson, daysOld: 2,
                                 note: "Still had it this week.")
        CoreDataTestHelpers.save(context)
        let toolDefinition = try DateRange.tool(named: "recall_checks", in: tools)

        let byDefault = try await toolDefinition.handler(["student_name": .string("Rae")])
        #expect(byDefault.contains("Still had it this week."))
        #expect(!byDefault.contains("two years back"))

        let widened = try await toolDefinition.handler([
            "student_name": .string("Rae"), "since": DateRange.dayText(1000)
        ])
        #expect(widened.contains("Lost it two years back."))

        let capped = try await toolDefinition.handler([
            "student_name": .string("Rae"),
            "since": DateRange.dayText(1000), "until": DateRange.dayText(600)
        ])
        #expect(capped.contains("Lost it two years back."))
        #expect(!capped.contains("Still had it this week."))

        await #expect(throws: MCPToolError.self) {
            _ = try await toolDefinition.handler([
                "student_name": .string("Rae"),
                "since": DateRange.dayText(2), "until": DateRange.dayText(700)
            ])
        }
    }
}
