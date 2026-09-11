import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// The `mark_mastered` call the report closes with, decoded.
private struct ProposedMarkList: Decodable {
    let marks: [ProposedMark]
}

private struct ProposedMark: Decodable {
    let lesson: String
    let studentNames: [String]

    enum CodingKeys: String, CodingKey {
        case lesson
        case studentNames = "student_names"
    }
}

@Suite("MCP Mastery Candidates Tool")
@MainActor
struct MCPMasteryCandidatesToolTests {

    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func day(_ iso: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: iso))
    }

    private func candidates(
        _ tools: [MCPToolDefinition], _ arguments: [String: JSONValue] = [:]
    ) async throws -> String {
        try await tool(named: "mastery_candidates", in: tools).handler(arguments)
    }

    /// Four girls and three lessons:
    /// - Avital: confirmed ready on the commutative law, unmarked — a candidate.
    /// - Nechama: the same, so a lesson grouping has two names to gather.
    /// - Dvora: confirmed on the same lesson but already marked mastered.
    /// - Etty: given the distributive law with no confirmation, but her
    ///   practice work for it came back complete — a weaker candidate.
    /// - Leora: withdrawn, confirmed on the commutative law.
    /// Nobody has been given the Bells lesson at all.
    private struct Classroom {
        let avital: CDStudent
        let nechama: CDStudent
        let dvora: CDStudent
        let etty: CDStudent
        let leora: CDStudent
        let commutative: CDLesson
        let distributive: CDLesson
        let bells: CDLesson
    }

    private func seedClassroom(in context: NSManagedObjectContext) throws -> Classroom {
        let avital = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Avital", lastName: "Beyderman", level: .upper
        )
        let nechama = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Nechama", lastName: "Roth", level: .upper
        )
        let dvora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Dvora", lastName: "Katz", level: .upper)
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Krinsky", level: .upper)
        let leora = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Leora", lastName: "Fleishchmann", level: .upper,
            enrollmentStatus: .withdrawn, dateWithdrawn: try day("2026-06-01")
        )
        let commutative = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Commutative Law of Multiplication", area: "Math", sequence: "Laws"
        )
        let distributive = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Distributive Law of Multiplication", area: "Math", sequence: "Laws"
        )
        let bells = CoreDataTestHelpers.seedLesson(in: context, name: "Bells", area: "Music", sequence: "Tone Bars")
        #expect(CoreDataTestHelpers.save(context))

        let classroom = Classroom(
            avital: avital, nechama: nechama, dvora: dvora, etty: etty, leora: leora,
            commutative: commutative, distributive: distributive, bells: bells
        )
        try seedRecord(classroom, in: context)
        return classroom
    }

    /// What the record holds about them: the commutative law confirmed for
    /// four girls (marked for one), and the distributive law given to Etty
    /// with a practice work that came back complete.
    private func seedRecord(_ classroom: Classroom, in context: NSManagedObjectContext) throws {
        let commutative = classroom.commutative
        let distributive = classroom.distributive
        for student in [classroom.avital, classroom.nechama, classroom.dvora, classroom.leora] {
            let presentation = PresentationFactory.makePresented(
                lesson: commutative, students: [student], presentedAt: try day("2026-03-11"), context: context
            )
            presentation.confirmStudent(try #require(student.id))
            let row = CDLessonPresentation(context: context)
            row.studentID = try #require(student.id).uuidString
            row.lessonID = try #require(commutative.id).uuidString
            row.state = .presented
            row.presentedAt = try day("2026-03-11")
            if student == classroom.dvora { row.masteredAt = try day("2026-04-01") }
        }

        let etty = classroom.etty
        _ = PresentationFactory.makePresented(
            lesson: distributive, students: [etty], presentedAt: try day("2026-02-02"), context: context
        )
        let ettyRow = CDLessonPresentation(context: context)
        ettyRow.studentID = try #require(etty.id).uuidString
        ettyRow.lessonID = try #require(distributive.id).uuidString
        ettyRow.state = .presented
        ettyRow.presentedAt = try day("2026-02-02")
        let practice = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Distributive law practice",
            studentID: try #require(etty.id), lessonID: try #require(distributive.id)
        )
        practice.kind = .practiceLesson
        practice.status = .complete
        practice.completedAt = try day("2026-02-20")
        #expect(CoreDataTestHelpers.save(context))
    }

    /// The last line of the report: the mark_mastered call it proposes.
    private func closingLine(_ output: String) throws -> String {
        let lines: [Substring] = output.split(separator: "\n")
        let last: Substring = try #require(lines.last)
        return String(last)
    }

    /// The `marks` array inside that line.
    private func closingMarks(_ output: String) throws -> [ProposedMark] {
        let data: Data = try #require(try closingLine(output).data(using: .utf8))
        let decoded: ProposedMarkList = try JSONDecoder().decode(ProposedMarkList.self, from: data)
        return decoded.marks
    }

    /// The children one lesson's mark names, in the order the call lists them.
    private func names(for lessonID: String, in marks: [ProposedMark]) throws -> [String] {
        let mark: ProposedMark = try #require(marks.first { $0.lesson == lessonID })
        return mark.studentNames
    }

    // MARK: - What counts as a candidate

    @Test("a confirmed but unmarked child is listed with the day she was confirmed")
    func listsConfirmedUnmarkedChild() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let commutativeID = try #require(classroom.commutative.id).uuidString

        let output = try await candidates(tools)

        #expect(output.hasPrefix("Mastery candidates (3) — presented, not yet marked, with evidence:"))
        #expect(output.contains("Avital Beyderman:"))
        #expect(output.contains("- [lesson id=\(commutativeID)] The Commutative Law of Multiplication "
            + "— confirmed ready 2026-03-11"))
        #expect(output.contains("Nothing has been marked. To confirm these as assessed, call mark_mastered with:"))

        let marks = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
            .filter { $0.masteredAt != nil && $0.studentID != (classroom.dvora.id?.uuidString ?? "") }
        #expect(marks.isEmpty, "the candidates tool must never mark anyone")
    }

    @Test("an already-mastered pair, a never-presented lesson and a withdrawn child are all left out")
    func excludesMarkedUnpresentedAndWithdrawn() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)

        let output = try await candidates(tools)

        #expect(!output.contains("Dvora Katz"), "her commutative-law row is already marked mastered")
        #expect(!output.contains("Bells"), "nobody has been given it, so there is nothing to assess")
        #expect(!output.contains("Leora Fleishchmann"), "she is withdrawn")
    }

    @Test("a completed practice work is evidence on its own")
    func listsCompletedPracticeWork() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let distributiveID = try #require(classroom.distributive.id).uuidString

        let output = try await candidates(tools)

        #expect(output.contains("Etty Krinsky:"))
        #expect(output.contains("- [lesson id=\(distributiveID)] The Distributive Law of Multiplication "
            + "— practice complete"))
        #expect(!output.contains("practice complete (proficient)"), "the work has no proficient outcome")
    }

    // MARK: - Shape of the report

    @Test("group_by lesson gathers every child under the one lesson")
    func groupsByLesson() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let commutativeID = try #require(classroom.commutative.id).uuidString

        let output = try await candidates(tools, ["group_by": .string("lesson")])

        #expect(output.contains(
            "[lesson id=\(commutativeID)] The Commutative Law of Multiplication — Math › Laws:"
        ))
        #expect(output.contains("- Avital Beyderman — confirmed ready 2026-03-11"))
        #expect(output.contains("- Nechama Roth — confirmed ready 2026-03-11"))
    }

    @Test("the closing JSON is valid and names the lesson and every child under it")
    func closesWithThePreciseMarkMasteredCall() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let report: String = try await candidates(tools)
        try expectProposedMarks(in: report, for: classroom)
    }

    /// The closing line is a JSON object, as promised.
    private func expectValidJSONObject(in report: String) throws {
        let line: String = try closingLine(report)
        let data: Data = try #require(line.data(using: .utf8))
        let parsed: Any = try JSONSerialization.jsonObject(with: data)
        let object: [String: Any]? = parsed as? [String: Any]
        #expect(object != nil, "the report must close with a JSON object")
    }

    /// One item per lesson, its children gathered under it.
    private func expectProposedMarks(in report: String, for classroom: Classroom) throws {
        try expectValidJSONObject(in: report)
        let marks: [ProposedMark] = try closingMarks(report)
        let commutativeID: String = try #require(classroom.commutative.id).uuidString
        let distributiveID: String = try #require(classroom.distributive.id).uuidString
        let confirmed: [String] = try names(for: commutativeID, in: marks)
        let practised: [String] = try names(for: distributiveID, in: marks)
        let expectedConfirmed: [String] = ["Avital Beyderman", "Nechama Roth"]
        let expectedPractised: [String] = ["Etty Krinsky"]
        #expect(marks.count == 2)
        #expect(confirmed == expectedConfirmed)
        #expect(practised == expectedPractised)
    }

    @Test("the closing JSON is a call mark_mastered accepts as given")
    func closingJSONFeedsMarkMastered() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let report: String = try await candidates(tools)
        let data: Data = try #require(try closingLine(report).data(using: .utf8))
        let arguments: [String: JSONValue] = try JSONDecoder().decode([String: JSONValue].self, from: data)

        let output: String = try await tool(named: "mark_mastered", in: tools).handler(arguments)

        #expect(output.contains("The Commutative Law of Multiplication"))
        let avitalID: String = try #require(classroom.avital.id).uuidString
        let commutativeID: String = try #require(classroom.commutative.id).uuidString
        let rows: [CDLessonPresentation] = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        let row: CDLessonPresentation = try #require(rows.first { presentation in
            presentation.studentID == avitalID && presentation.lessonID == commutativeID
        })
        #expect(row.state == .proficient)
    }

    // MARK: - Narrowing

    @Test("area narrows to one curriculum area, case-insensitively")
    func filtersByArea() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)

        let math = try await candidates(tools, ["area": .string("math")])
        #expect(math.contains("Avital Beyderman"))
        #expect(math.contains("Etty Krinsky"))

        let music = try await candidates(tools, ["area": .string("Music")])
        #expect(music == "No candidates: every presented lesson with evidence is already marked, "
            + "or there is no evidence yet.")
    }

    @Test("student narrows the report to one child")
    func filtersByStudent() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)
        let arguments: [String: JSONValue] = ["student": .string("Etty")]

        let output: String = try await candidates(tools, arguments)

        #expect(output.hasPrefix("Mastery candidates (1)"))
        #expect(output.contains("Etty Krinsky:"))
        #expect(!output.contains("Avital"))
    }

    @Test("limit truncates the ranking and says how many it held back")
    func limitTruncatesTheRanking() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)
        let arguments: [String: JSONValue] = ["limit": .int(1)]

        let output: String = try await candidates(tools, arguments)

        #expect(output.hasPrefix("Mastery candidates (1)"))
        #expect(output.contains("2 more candidate(s) not shown; raise limit to see them."))
        #expect(output.contains("Avital Beyderman"), "the strongest, oldest candidate survives the cut")
        let proposed: [ProposedMark] = try closingMarks(output)
        #expect(proposed.count == 1, "the closing call proposes only what it showed")
    }
}
