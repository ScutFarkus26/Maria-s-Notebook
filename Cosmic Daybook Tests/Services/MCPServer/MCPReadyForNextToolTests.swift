import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `students_ready` — the two groupings, the narrowing arguments, and the
/// closing call, which has to be a call the model can hand straight back to
/// `schedule_presentation` rather than a sentence about one.
@Suite("MCP Students Ready Tool")
@MainActor
struct MCPReadyForNextToolTests {

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

    // MARK: - Fixture

    /// Math › Laws runs Commutative → Distributive → Associative.
    ///
    /// - Avital: confirmed on Commutative → ready for Distributive
    /// - Etty: confirmed on Commutative → ready for Distributive
    /// - Ora: confirmed on Commutative, with her own practice still open and
    ///   the sub-area requiring practice → almost ready for Distributive
    /// - Malka: mastered (never confirmed) on Distributive → ready for
    ///   Associative
    /// - Rivka: withdrawn, confirmed on Commutative → must not appear
    /// - Sarah: enrolled, no record at all
    private struct Classroom {
        let commutative: CDLesson
        let distributive: CDLesson
        let associative: CDLesson
        let avital: CDStudent
        let etty: CDStudent
        let ora: CDStudent
        let malka: CDStudent
    }

    @discardableResult
    private func confirm(
        _ student: CDStudent, on lesson: CDLesson, at when: Date, in context: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        let given = PresentationFactory.makePresented(
            lesson: lesson, students: [student], presentedAt: when, context: context
        )
        given.confirmStudent(try #require(student.id))
        return given
    }

    /// Math › Laws asks for practice, and the child's own sheet is still open.
    private func seedPracticeGate(
        holding student: CDStudent, on lesson: CDLesson, in context: NSManagedObjectContext
    ) throws {
        let settings = CDLessonSequenceSettings(context: context)
        settings.area = "Math"
        settings.sequence = "Laws"
        settings.requiresPractice = true
        settings.requiresTeacherConfirmation = false
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "\(lesson.name) practice",
            studentID: try #require(student.id), lessonID: try #require(lesson.id)
        )
        work.statusRaw = "active"
    }

    @discardableResult
    private func seedClassroom(in context: NSManagedObjectContext) throws -> Classroom {
        func lesson(_ name: String, _ order: Int64) -> CDLesson {
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: name, area: "Math", sequence: "Laws"
            )
            lesson.orderInSequence = order
            return lesson
        }
        let commutative = lesson("Commutative Law", 10)
        let distributive = lesson("Distributive Law", 20)
        let associative = lesson("Associative Law", 30)
        // A lesson in another area, so the area filter has something to drop.
        let bells = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bells", area: "Music", sequence: "Tone Bars"
        )
        bells.orderInSequence = 10
        let chimes = CoreDataTestHelpers.seedLesson(
            in: context, name: "Chime Bars", area: "Music", sequence: "Tone Bars"
        )
        chimes.orderInSequence = 20

        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Krinsky")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let malka = CoreDataTestHelpers.seedStudent(in: context, firstName: "Malka", lastName: "Stern")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Adler")
        let rivka = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rivka", lastName: "Gold", enrollmentStatus: .withdrawn
        )
        #expect(CoreDataTestHelpers.save(context))

        try confirm(avital, on: commutative, at: try day("2026-03-11"), in: context)
        try confirm(etty, on: commutative, at: try day("2026-03-11"), in: context)
        try confirm(ora, on: commutative, at: try day("2026-03-11"), in: context)
        try confirm(rivka, on: commutative, at: try day("2026-03-11"), in: context)
        // Avital is also ready in Music, so the area filter has work to do.
        try confirm(avital, on: bells, at: try day("2026-03-04"), in: context)

        PresentationFactory.makePresented(
            lesson: distributive, students: [malka], presentedAt: try day("2026-01-20"), context: context
        )
        let proficiency = CDLessonPresentation(context: context)
        proficiency.studentID = try #require(malka.id).uuidString
        proficiency.lessonID = try #require(distributive.id).uuidString
        proficiency.presentedAt = try day("2026-01-20")
        proficiency.masteredAt = try day("2026-02-15")

        try seedPracticeGate(holding: ora, on: commutative, in: context)
        #expect(CoreDataTestHelpers.save(context))

        return Classroom(
            commutative: commutative, distributive: distributive, associative: associative,
            avital: avital, etty: etty, ora: ora, malka: malka
        )
    }

    // MARK: - Groupings

    @Test("Grouped by student, each child's next lessons with the mark behind them")
    func groupedByStudent() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let distributiveID = try #require(classroom.distributive.id).uuidString
        let associativeID = try #require(classroom.associative.id).uuidString

        let output = try await tool(named: "students_ready", in: tools).handler([:])

        #expect(output.contains("Avital Beyderman:"))
        #expect(output.contains(
            "- [lesson id=\(distributiveID)] Distributive Law — after Commutative Law (confirmed 2026-03-11)"
        ))
        #expect(output.contains(
            "- [lesson id=\(associativeID)] Associative Law — after Distributive Law (mastered 2026-01-20)"
        ))
        // Ora's practice is still open, so her line says what is holding her.
        let oraLine = try #require(output.split(separator: "\n").map(String.init).first {
            $0.contains(distributiveID) && $0.contains("almost:")
        })
        #expect(oraLine.hasSuffix(" — almost: practice on Commutative Law not yet complete"))
        #expect(output.contains("Ora Levi:"))
        #expect(!output.contains("Rivka"))
        #expect(!output.contains("Sarah Adler:"))
    }

    @Test("Grouped by lesson, with the schedule_presentation call that forms the group")
    func groupedByLessonClosesWithTheCall() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let distributiveID = try #require(classroom.distributive.id).uuidString

        let output = try await tool(named: "students_ready", in: tools).handler([
            "group_by": .string("lesson")
        ])
        let lines = output.split(separator: "\n").map(String.init)

        let header = try #require(lines.first { $0.contains(distributiveID) && $0.contains("ready (") })
        #expect(header.contains("Distributive Law — Math › Laws"))
        #expect(header.contains("ready (2): Avital Beyderman, Etty Krinsky"))
        #expect(header.contains("almost ready (1): Ora Levi (practice on Commutative Law not yet complete)"))

        // The closing line has to decode as a call, not merely look like one.
        let callLine = try #require(lines.first {
            $0.hasPrefix("To schedule: ") && $0.contains(distributiveID)
        })
        let json = String(callLine.dropFirst("To schedule: ".count))
        let call = try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
        #expect(call["name"]?.stringValue == "schedule_presentation")
        let arguments = try #require(call["arguments"])
        #expect(arguments["lesson"]?.stringValue == distributiveID)
        #expect(arguments["student_names"]?.arrayValue?.compactMap(\.stringValue)
            == ["Avital Beyderman", "Etty Krinsky"])

        // Only the ready children are offered, and on a day school is in.
        let dateText = try #require(arguments["date"]?.stringValue)
        let proposed = try #require(MCPNotebookTools.isoDay.date(from: dateText))
        #expect(proposed > AppCalendar.startOfDay(Date()))
        #expect(!SchoolCalendarService.shared.isNonSchoolDaySync(proposed, using: context))
    }

    // MARK: - Narrowing

    @Test("basis, include_almost_ready, student and area each narrow the queue")
    func narrowingArguments() async throws {
        let (tools, context) = try makeTools()
        try seedClassroom(in: context)
        let ready = try tool(named: "students_ready", in: tools)

        // Only mastery marks: Malka's Associative Law, and nobody else's.
        let byProficiencyMark = try await ready.handler(["basis": .string("mastered")])
        #expect(byProficiencyMark.contains("Malka Stern:"))
        #expect(byProficiencyMark.contains("Associative Law"))
        #expect(!byProficiencyMark.contains("Avital Beyderman:"))

        let confirmed = try await ready.handler(["basis": .string("confirmed")])
        #expect(confirmed.contains("Avital Beyderman:"))
        #expect(!confirmed.contains("Malka Stern:"))

        // Almost-ready hidden: Ora drops out entirely, she has nothing else.
        let readyOnly = try await ready.handler(["include_almost_ready": .bool(false)])
        #expect(!readyOnly.contains("Ora Levi:"))
        #expect(readyOnly.contains("Avital Beyderman:"))
        #expect(try await ready.handler([:]).contains("Ora Levi:"))

        // One child, and one area.
        let justOra = try await ready.handler(["student": .string("Ora")])
        #expect(justOra.contains("Ora Levi:"))
        #expect(!justOra.contains("Avital Beyderman:"))

        let music = try await ready.handler(["student": .string("Avital"), "area": .string("Music")])
        #expect(music.contains("Chime Bars"))
        #expect(!music.contains("Distributive Law"))
    }

    @Test("An empty queue says so, and a withdrawn child never fills it")
    func emptyQueueAndWithdrawnChild() async throws {
        let (tools, context) = try makeTools()
        let ready = try tool(named: "students_ready", in: tools)

        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Commutative Law", area: "Math", sequence: "Laws"
        )
        lesson.orderInSequence = 10
        let next = CoreDataTestHelpers.seedLesson(
            in: context, name: "Distributive Law", area: "Math", sequence: "Laws"
        )
        next.orderInSequence = 20
        let rivka = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rivka", lastName: "Gold", enrollmentStatus: .withdrawn
        )
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Adler")
        #expect(CoreDataTestHelpers.save(context))
        try confirm(rivka, on: lesson, at: try day("2026-03-11"), in: context)
        #expect(CoreDataTestHelpers.save(context))

        let output = try await ready.handler([:])
        #expect(output == "Nobody is waiting on a next lesson: every confirmed or mastered "
            + "lesson's successor is given or planned.")
    }

    @Test("students_ready is registered read-only")
    func toolIsReadOnly() throws {
        let (tools, _) = try makeTools()
        let ready = try tool(named: "students_ready", in: tools)
        #expect(ready.annotations.readOnlyHint)
        #expect(!ready.annotations.destructiveHint)
    }
}
