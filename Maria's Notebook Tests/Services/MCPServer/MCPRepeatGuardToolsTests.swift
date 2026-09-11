import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// The regive guard on `schedule_presentation` and `record_presentation`: a
/// lesson a named child already has on record is refused until the call says
/// why she is having it again.
@Suite("MCP Regive Guard")
@MainActor
struct MCPRepeatGuardToolsTests {
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

    /// Ora had the Checkerboard on 2026-03-11; Etty never has. Racks and Tubes
    /// is a second lesson neither of them has had.
    private struct Regive {
        let checkerboard: CDLesson
        let racks: CDLesson
        let ora: CDStudent
        let etty: CDStudent
        let prior: CDLessonAssignment
    }

    private func seedRegive(in context: NSManagedObjectContext) throws -> Regive {
        let checkerboard = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let racks = CoreDataTestHelpers.seedLesson(
            in: context, name: "Racks and Tubes", area: "Math", sequence: "Division"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        let prior = PresentationFactory.makePresented(
            lesson: checkerboard, students: [ora], presentedAt: try day("2026-03-11"), context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        return Regive(checkerboard: checkerboard, racks: racks, ora: ora, etty: etty, prior: prior)
    }

    // MARK: - schedule_presentation

    @Test("schedule_presentation refuses a lesson a named child already has, and writes nothing")
    func schedulePresentationRefusesARegive() async throws {
        let (tools, context) = try makeTools()
        let seeded = try seedRegive(in: context)

        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "schedule_presentation", in: tools).handler([
                "lesson": .string("Checkerboard"),
                "student_names": .array([.string("Ora"), .string("Etty")]),
                "date": .string("2026-09-16")
            ])
        }
        let message: String = refusal?.message ?? ""
        #expect(message.hasPrefix("schedule_presentation refused — nothing has been changed."))
        #expect(message.contains("1 of these 2 already has \"Checkerboard\" on record: Ora Levi (2026-03-11)."))
        #expect(names(message))

        // The prior record is the only assignment, untouched.
        let untouched: Bool = assignments(in: context) == [seeded.prior]
            && !seeded.prior.needsAnotherPresentation
        #expect(untouched)
    }

    /// The refusal names both ways out and where to look them up.
    private func names(_ message: String) -> Bool {
        message.contains("purpose: \"second_pass\"")
            && message.contains("purpose: \"review\"")
            && message.contains("student_presentation_history")
    }

    @Test("purpose second_pass schedules it, flags the earlier record, and says so on the draft")
    func schedulePresentationSecondPass() async throws {
        let (tools, context) = try makeTools()
        let seeded = try seedRegive(in: context)

        let receipt = try await tool(named: "schedule_presentation", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Ora")]),
            "date": .string("2026-09-16"),
            "purpose": .string("second_pass")
        ])
        #expect(receipt.contains("— 1 of 1 already had it (second pass noted)."))

        #expect(seeded.prior.needsAnotherPresentation)
        let draft = try #require(assignments(in: context).first { $0 != seeded.prior })
        #expect(draft.notes == "Second pass — planned 2026-09-16")
        #expect(draft.scheduledForDay == AppCalendar.startOfDay(try day("2026-09-16")))
    }

    @Test("purpose review notes the revisit without calling the earlier record a failure")
    func schedulePresentationReview() async throws {
        let (tools, context) = try makeTools()
        let seeded = try seedRegive(in: context)

        let receipt = try await tool(named: "schedule_presentation", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Ora")]),
            "date": .string("2026-09-16"),
            "purpose": .string("review")
        ])
        #expect(receipt.contains("(review noted)."))

        #expect(!seeded.prior.needsAnotherPresentation)
        let draft = try #require(assignments(in: context).first { $0 != seeded.prior })
        #expect(draft.notes == "Review — planned 2026-09-16")
    }

    @Test("purpose on a lesson nobody has had is accepted and says as much")
    func schedulePresentationPurposeWithoutConflicts() async throws {
        let (tools, context) = try makeTools()
        _ = try seedRegive(in: context)

        let receipt = try await tool(named: "schedule_presentation", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Etty")]),
            "date": .string("2026-09-16"),
            "purpose": .string("second_pass")
        ])
        #expect(receipt.contains("(nobody had it before; purpose noted)."))
    }

    @Test("an unknown purpose is refused with the two words that are allowed")
    func schedulePresentationRejectsUnknownPurpose() async throws {
        let (tools, context) = try makeTools()
        let seeded = try seedRegive(in: context)

        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "schedule_presentation", in: tools).handler([
                "lesson": .string("Checkerboard"),
                "student_names": .array([.string("Ora")]),
                "date": .string("2026-09-16"),
                "purpose": .string("again")
            ])
        }
        let message = try #require(refusal?.message)
        #expect(message.contains("\"second_pass\" or \"review\""))
        #expect(assignments(in: context) == [seeded.prior])
    }

    @Test("schedule_presentation refuses a day school is not in session and plans nothing")
    func schedulePresentationRefusesNonSchoolDay() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads", area: "Math", sequence: "Decimal")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)

        // 2026-09-12 is a Saturday.
        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "schedule_presentation", in: tools).handler([
                "lesson": .string("Golden Beads"),
                "student_names": .array([.string("Maya")]),
                "date": .string("2026-09-12")
            ])
        }
        #expect(refusal?.message == "School is not in session on 2026-09-12 (Saturday); "
            + "nothing was scheduled. Choose a school day.")
        #expect(assignments(in: context).isEmpty)
    }

    // MARK: - record_presentation

    @Test("one repeat in a batch refuses the whole call and files none of it")
    func recordPresentationRefusesARegiveInABatch() async throws {
        let (tools, context) = try makeTools()
        let seeded = try seedRegive(in: context)
        let batch: [String: JSONValue] = [
            "presentations": .array([
                .object([
                    "lesson": .string("Racks and Tubes"),
                    "student_names": .array([.string("Etty")]),
                    "date": .string("2026-09-16")
                ]),
                .object([
                    "lesson": .string("Checkerboard"),
                    "student_names": .array([.string("Ora")]),
                    "date": .string("2026-09-16")
                ])
            ])
        ]

        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "record_presentation", in: tools).handler(batch)
        }
        let message = try #require(refusal?.message)
        #expect(message.hasPrefix("record_presentation refused — nothing has been changed."))
        #expect(message.contains("Ora Levi already has \"Checkerboard\" on record (2026-03-11)."))

        // Not even the unobjectionable half of the batch was written.
        #expect(assignments(in: context) == [seeded.prior])
    }

    @Test("re-filing the same lesson, children and day is an edit, not a repeat")
    func recordPresentationSameDayRefileIsExempt() async throws {
        let (tools, context) = try makeTools()
        _ = try seedRegive(in: context)
        let record = try tool(named: "record_presentation", in: tools)
        let call: [String: JSONValue] = [
            "lesson": .string("Racks and Tubes"),
            "student_names": .array([.string("Etty")]),
            "date": .string("2026-09-16"),
            "group_observation": .string("She named every hierarchy.")
        ]

        _ = try await record.handler(call)
        let second = try await record.handler(call)
        #expect(second.contains("Updated the presentation already recorded"))
        // The prior Checkerboard record, plus the one Racks and Tubes record
        // the two calls share.
        #expect(assignments(in: context).count == 2)
    }

    @Test("completing a plan is exempt — the plan already answered the question")
    func recordPresentationPlannedLessonIsExempt() async throws {
        let (tools, context) = try makeTools()
        let seeded = try seedRegive(in: context)
        _ = PresentationFactory.makeScheduled(
            lesson: seeded.checkerboard, students: [seeded.ora],
            scheduledFor: try day("2026-09-16"), context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "record_presentation", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Ora")]),
            "date": .string("2026-09-16")
        ])
        #expect(output.contains("Recorded the lesson planned for them"))
        #expect(assignments(in: context).count == 2)
    }

    @Test("purpose files the repeat and flags the earlier record for re-teaching")
    func recordPresentationWithPurposeFilesAndFlags() async throws {
        let (tools, context) = try makeTools()
        let seeded = try seedRegive(in: context)

        let output = try await tool(named: "record_presentation", in: tools).handler([
            "lesson": .string("Checkerboard"),
            "student_names": .array([.string("Ora")]),
            "date": .string("2026-09-16"),
            "purpose": .string("second_pass"),
            "group_observation": .string("Took the exchange on her own this time.")
        ])
        #expect(output.contains("1 of 1 already had it (second pass noted)."))

        #expect(seeded.prior.needsAnotherPresentation)
        let filed = try #require(assignments(in: context).first { $0 != seeded.prior })
        #expect(filed.isPresented)
        #expect(filed.notes == "Second pass — planned 2026-09-16")
    }
}
