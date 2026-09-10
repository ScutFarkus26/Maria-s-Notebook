import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("MCP Mastery Tools")
@MainActor
struct MCPProficiencyMarkToolTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func day(_ iso: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)!
    }

    /// Two girls, a two-step track, and one presented-but-unmastered row each
    /// on its first lesson. Nobody has a row on the second lesson.
    private struct Classroom {
        let avital: CDStudent
        let etty: CDStudent
        let commutative: CDLesson
        let distributive: CDLesson
        let track: CDTrackEntity
    }

    private func seedClassroom(in context: NSManagedObjectContext) throws -> Classroom {
        let avital = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Avital", lastName: "Beyderman", level: .upper
        )
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Krinsky", level: .upper)
        let commutative = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Commutative Law of Multiplication", area: "Math", sequence: "Laws"
        )
        commutative.orderInSequence = 0
        let distributive = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Distributive Law of Multiplication", area: "Math", sequence: "Laws"
        )
        distributive.orderInSequence = 1
        let track = try SequenceTrackService.getOrCreateTrack(area: "Math", sequence: "Laws", context: context)

        for student in [avital, etty] {
            let row = CDLessonPresentation(context: context)
            row.studentID = try #require(student.id).uuidString
            row.lessonID = try #require(commutative.id).uuidString
            row.state = .presented
            row.presentedAt = day("2026-03-11")
            row.lastObservedAt = day("2026-03-11")
        }
        #expect(CoreDataTestHelpers.save(context))
        return Classroom(avital: avital, etty: etty, commutative: commutative, distributive: distributive, track: track)
    }

    private func rows(
        for student: CDStudent, lesson: CDLesson, in context: NSManagedObjectContext
    ) -> [CDLessonPresentation] {
        context.safeFetch(CDFetchRequest(CDLessonPresentation.self)).filter {
            $0.studentID == student.id?.uuidString && $0.lessonID == lesson.id?.uuidString
        }
    }

    private func proficientSteps(
        for student: CDStudent, on track: CDTrackEntity, in context: NSManagedObjectContext
    ) -> Int {
        let studentID = student.id?.uuidString ?? ""
        let presentations = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
            .filter { $0.studentID == studentID }
        return TrackProgressResolver.proficientCount(
            track: track, studentID: studentID, lessonPresentations: presentations
        )
    }

    // MARK: - Parity with the checklist

    @Test("mark_mastered flips the row in place and counts the same as a checklist mark")
    func markMatchesChecklistPath() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        #expect(TrackProgressResolver.totalSteps(track: classroom.track) == 2)
        #expect(proficientSteps(for: classroom.avital, on: classroom.track, in: context) == 0)

        let output = try await tool(named: "mark_mastered", in: tools).handler([
            "lesson": .string("The Commutative Law of Multiplication"),
            "student_names": .array([.string("Avital")]),
            "date": .string("2026-09-09")
        ])

        // Etty gets the same mark through the checklist's batch path.
        let prefetched = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        ChecklistBatchActionExecutor.upsertLessonPresentation(
            studentID: try #require(classroom.etty.id).uuidString,
            lessonID: try #require(classroom.commutative.id).uuidString,
            state: .proficient,
            from: prefetched,
            context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let avitalRows = rows(for: classroom.avital, lesson: classroom.commutative, in: context)
        #expect(avitalRows.count == 1, "the existing row is mutated, not joined by a second one")
        #expect(avitalRows.first?.state == .proficient)
        #expect(avitalRows.first?.masteredAt == day("2026-09-09"))
        #expect(rows(for: classroom.etty, lesson: classroom.commutative, in: context).count == 1)

        let avitalCount = proficientSteps(for: classroom.avital, on: classroom.track, in: context)
        let ettyCount = proficientSteps(for: classroom.etty, on: classroom.track, in: context)
        #expect(avitalCount == 1)
        #expect(avitalCount == ettyCount, "an MCP mark and a checklist mark must read identically")

        #expect(output.contains("Marked mastered on 2026-09-09: [lesson id="))
        #expect(output.contains("The Commutative Law of Multiplication — Math › Laws"))
        #expect(output.contains("- Avital Beyderman — Math — Laws: 1/2 steps mastered"))
    }

    // MARK: - Refusals

    @Test("mark_mastered refuses a child with no presentation on record and writes nothing")
    func refusesUnrecordedChildAndLeavesOthersUntouched() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)

        do {
            _ = try await tool(named: "mark_mastered", in: tools).handler([
                "lesson": .string("The Commutative Law of Multiplication"),
                "student_names": .array([.string("Avital"), .string("Etty")]),
                "date": .string("2026-09-09")
            ])
        } catch {
            Issue.record("both girls have a row on the commutative law; this should not refuse: \(error)")
        }

        do {
            _ = try await tool(named: "mark_mastered", in: tools).handler([
                "lesson": .string("The Distributive Law of Multiplication"),
                "student_names": .array([.string("Avital"), .string("Etty")])
            ])
            Issue.record("expected a refusal: nobody has a distributive-law presentation")
        } catch let error as MCPToolError {
            #expect(error.message.contains("No presentation of \"The Distributive Law of Multiplication\""))
            #expect(error.message.contains("Avital Beyderman, Etty Krinsky"))
            #expect(error.message.contains("nothing was marked"))
        }
        #expect(rows(for: classroom.avital, lesson: classroom.distributive, in: context).isEmpty)
        #expect(rows(for: classroom.etty, lesson: classroom.distributive, in: context).isEmpty)
    }

    @Test("mark_mastered refuses the whole call when only some children have a record")
    func refusesPartiallyRecordedGroup() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)
        let leora = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Leora", lastName: "Fleishchmann", level: .upper
        )
        #expect(CoreDataTestHelpers.save(context))
        _ = leora

        do {
            _ = try await tool(named: "mark_mastered", in: tools).handler([
                "lesson": .string("The Commutative Law of Multiplication"),
                "student_names": .array([.string("Avital"), .string("Leora")])
            ])
            Issue.record("expected a refusal: Leora has no presentation on record")
        } catch let error as MCPToolError {
            #expect(error.message.contains("Leora Fleishchmann"))
            #expect(!error.message.contains("Avital"))
        }
        let avitalRow = try #require(rows(for: classroom.avital, lesson: classroom.commutative, in: context).first)
        #expect(avitalRow.state == .presented, "a refused call must not have marked Avital either")
        #expect(avitalRow.masteredAt == nil)
    }

    // MARK: - Dating

    @Test("mark_mastered defaults to today and leaves an already-mastered row as recorded")
    func defaultsToTodayAndKeepsEarlierMark() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)

        _ = try await tool(named: "mark_mastered", in: tools).handler([
            "lesson": .string("The Commutative Law of Multiplication"),
            "student_names": .array([.string("Avital")])
        ])
        let row = try #require(rows(for: classroom.avital, lesson: classroom.commutative, in: context).first)
        let firstMark = try #require(row.masteredAt)
        #expect(Calendar.current.isDateInToday(firstMark))

        let output = try await tool(named: "mark_mastered", in: tools).handler([
            "lesson": .string("The Commutative Law of Multiplication"),
            "student_names": .array([.string("Avital")]),
            "date": .string("2026-01-01")
        ])
        #expect(output.contains("Already mastered, left as recorded:"))
        #expect(output.contains("- Avital Beyderman (mastered \(MCPNotebookTools.isoDay.string(from: firstMark)))"))
        #expect(row.masteredAt == firstMark)
        #expect(rows(for: classroom.avital, lesson: classroom.commutative, in: context).count == 1)
    }

    @Test("mark_mastered accepts a back-dated assessment and rejects a malformed date")
    func honoursDateOverride() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)

        _ = try await tool(named: "mark_mastered", in: tools).handler([
            "lesson": .string("The Commutative Law of Multiplication"),
            "student_names": .array([.string("Etty")]),
            "date": .string("2026-09-02")
        ])
        let row = try #require(rows(for: classroom.etty, lesson: classroom.commutative, in: context).first)
        #expect(row.state == .proficient)
        #expect(row.masteredAt == day("2026-09-02"))
        #expect(row.lastObservedAt == day("2026-09-02"))

        do {
            _ = try await tool(named: "mark_mastered", in: tools).handler([
                "lesson": .string("The Commutative Law of Multiplication"),
                "student_names": .array([.string("Avital")]),
                "date": .string("Tuesday")
            ])
            Issue.record("expected a malformed-date refusal")
        } catch let error as MCPToolError {
            #expect(error.message.contains("YYYY-MM-DD"))
        }
        let avitalRow = try #require(rows(for: classroom.avital, lesson: classroom.commutative, in: context).first)
        #expect(avitalRow.state == .presented)
    }
}
