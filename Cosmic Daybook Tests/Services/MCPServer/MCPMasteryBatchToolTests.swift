import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `mark_mastered`'s `marks` batch: several lessons confirmed in one call,
/// resolved in full before anything is written.
@Suite("MCP Mastery Batch")
@MainActor
struct MCPMasteryBatchToolTests {

    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    /// Two girls and a two-step track, each girl with a presented-but-unmarked
    /// row on both steps, so one batch has two lessons to mark.
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
            for (lesson, presented) in [(commutative, "2026-03-11"), (distributive, "2026-04-02")] {
                let row = CDLessonPresentation(context: context)
                row.studentID = try #require(student.id).uuidString
                row.lessonID = try #require(lesson.id).uuidString
                row.state = .presented
                row.presentedAt = try CoreDataTestHelpers.day(presented)
            }
        }
        #expect(CoreDataTestHelpers.save(context))
        return Classroom(
            avital: avital, etty: etty, commutative: commutative, distributive: distributive, track: track
        )
    }

    private func row(
        for student: CDStudent, lesson: CDLesson, in context: NSManagedObjectContext
    ) throws -> CDLessonPresentation {
        try #require(context.safeFetch(CDFetchRequest(CDLessonPresentation.self)).first {
            $0.studentID == student.id?.uuidString && $0.lessonID == lesson.id?.uuidString
        })
    }

    private func markedRows(in context: NSManagedObjectContext) -> [CDLessonPresentation] {
        context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
            .filter { $0.masteredAt != nil || $0.state == .proficient }
    }

    // MARK: - Marking

    @Test("a marks batch marks two lessons for two children in one call")
    func marksBatchCoversEveryLesson() async throws {
        let (tools, context) = try makeTools()
        let classroom = try seedClassroom(in: context)

        let output = try await tool(named: "mark_mastered", in: tools).handler([
            "marks": .array([
                .object([
                    "lesson": .string("The Commutative Law of Multiplication"),
                    "student_names": .array([.string("Avital"), .string("Etty")]),
                    "date": .string("2026-09-09")
                ]),
                .object([
                    "lesson": .string("The Distributive Law of Multiplication"),
                    "student_names": .array([.string("Avital"), .string("Etty")]),
                    "date": .string("2026-09-10")
                ])
            ])
        ])

        for student in [classroom.avital, classroom.etty] {
            let commutative = try row(for: student, lesson: classroom.commutative, in: context)
            #expect(commutative.state == .proficient)
            #expect(commutative.masteredAt == (try CoreDataTestHelpers.day("2026-09-09")))
            let distributive = try row(for: student, lesson: classroom.distributive, in: context)
            #expect(distributive.state == .proficient)
            #expect(distributive.masteredAt == (try CoreDataTestHelpers.day("2026-09-10")))
        }
        #expect(output.contains("Marked mastered on 2026-09-09: [lesson id="))
        #expect(output.contains("Marked mastered on 2026-09-10: [lesson id="))
        #expect(output.contains("- Etty Krinsky — Math — Laws: 2/2 steps mastered"))
    }

    // MARK: - Refusals

    @Test("a marks batch naming one unrecorded child writes nothing at all")
    func marksBatchRefusesTheWholeCall() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)
        _ = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Leora", lastName: "Fleishchmann", level: .upper
        )
        #expect(CoreDataTestHelpers.save(context))

        do {
            _ = try await tool(named: "mark_mastered", in: tools).handler([
                "marks": .array([
                    .object([
                        "lesson": .string("The Commutative Law of Multiplication"),
                        "student_names": .array([.string("Avital"), .string("Etty")])
                    ]),
                    .object([
                        "lesson": .string("The Distributive Law of Multiplication"),
                        "student_names": .array([.string("Avital"), .string("Leora")])
                    ])
                ])
            ])
            Issue.record("expected a refusal: Leora has no distributive-law presentation")
        } catch let error as MCPToolError {
            #expect(error.message.contains("marks[1]:"))
            #expect(error.message.contains("No presentation of \"The Distributive Law of Multiplication\""))
            #expect(error.message.contains("Leora Fleishchmann"))
            #expect(error.message.contains("nothing was marked"))
        }

        #expect(markedRows(in: context).isEmpty, "a refused batch must leave every row exactly as it was")
    }

    @Test("mark_mastered refuses a call that mixes the single form with marks")
    func refusesBothFormsAtOnce() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)

        do {
            _ = try await tool(named: "mark_mastered", in: tools).handler([
                "lesson": .string("The Commutative Law of Multiplication"),
                "student_names": .array([.string("Avital")]),
                "marks": .array([
                    .object([
                        "lesson": .string("The Commutative Law of Multiplication"),
                        "student_names": .array([.string("Etty")])
                    ])
                ])
            ])
            Issue.record("expected a refusal: one lesson's fields and a marks array together")
        } catch let error as MCPToolError {
            #expect(error.message.contains("not both"))
        }
        #expect(markedRows(in: context).isEmpty)
    }

    @Test("an empty marks array is refused rather than reported as a no-op")
    func refusesEmptyBatch() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)

        do {
            _ = try await tool(named: "mark_mastered", in: tools).handler(["marks": .array([])])
            Issue.record("expected a refusal: marks is empty")
        } catch let error as MCPToolError {
            #expect(error.message.contains("marks is empty"))
        }
    }
}
