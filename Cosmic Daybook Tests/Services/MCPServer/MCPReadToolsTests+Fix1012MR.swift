import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12, agent MR, continued: mastery evidence (#7),
// former families (#12), repeat ordinals under `since` (#13) and the smaller
// items (#14). The parent-report items (#10, #11, #20) went with Parent
// Reports (2026-11-21).

@Suite("MCP families, history and reports (Fix1012MR)")
@MainActor
struct MCPReadToolsFix1012MRTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func call(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async throws -> String {
        let tool = try #require(tools.first { $0.name == name })
        return try await tool.handler(arguments)
    }

    private func refusal(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async -> String? {
        do {
            _ = try await call(name, arguments, in: tools)
            return nil
        } catch let error as MCPToolError {
            return error.message
        } catch {
            return "unexpected: \(error)"
        }
    }

    // MARK: - #7 / #14: mastery_candidates

    @Test("Keep Practicing and Incomplete practice are not evidence of mastery")
    func keepPracticingIsNotEvidence() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Frame", area: "Math", sequence: "Operations"
        )
        let lessonID = try #require(lesson.id)
        var expected: [String: WorkStatus] = [:]
        for (first, status) in [("Ora", WorkStatus.keepPracticing), ("Etty", .incomplete), ("Dalia", .mastered)] {
            let student = CoreDataTestHelpers.seedStudent(in: context, firstName: first, lastName: "Test")
            let studentID = try #require(student.id)
            _ = PresentationFactory.makePresented(
                lesson: lesson, students: [student],
                presentedAt: try CoreDataTestHelpers.day("2026-09-01"), context: context
            )
            let row = CDLessonPresentation(context: context)
            row.studentID = studentID.uuidString
            row.lessonID = lessonID.uuidString
            row.state = .presented
            row.presentedAt = try CoreDataTestHelpers.day("2026-09-01")
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Bead frame practice", studentID: studentID, lessonID: lessonID
            )
            work.kind = .practiceLesson
            work.status = status
            work.completedAt = try CoreDataTestHelpers.day("2026-09-10")
            expected[first] = status
        }
        #expect(CoreDataTestHelpers.save(context))

        let output = try await call("class_progress", ["view": "mastery_candidates"], in: tools)

        #expect(!output.contains("Ora Test"), "Keep Practicing is not mastery")
        #expect(!output.contains("Etty Test"), "Incomplete is not mastery")
        #expect(output.contains("Dalia Test:"))
        #expect(output.contains("practice mastered"))
        #expect(expected.count == 3)
    }

    @Test("a confirmation is not dated with the latest giving")
    func confirmationIsNotDatedAsTheLatestGiving() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Frame", area: "Math", sequence: "Operations"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let first = PresentationFactory.makePresented(
            lesson: lesson, students: [ora], presentedAt: try CoreDataTestHelpers.day("2026-03-02"), context: context
        )
        first.confirmStudent(try #require(ora.id))
        _ = PresentationFactory.makePresented(
            lesson: lesson, students: [ora], presentedAt: try CoreDataTestHelpers.day("2026-09-08"), context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let output = try await call("class_progress", ["view": "mastery_candidates"], in: tools)

        #expect(!output.contains("confirmed ready 2026-09-08"))
        #expect(output.contains("confirmed ready (last given 2026-09-08)"))
    }

    // MARK: - #12: list_guardians

    @Test("the whole-class guardian list leaves out families of children who left")
    func guardiansListLeavesOutFormerFamilies() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let rivka = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Rivka", lastName: "Gold", enrollmentStatus: .withdrawn
        )
        for (student, name) in [(maya, "Rosa Soto"), (rivka, "Dina Gold")] {
            let guardian = CDGuardian(context: context)
            guardian.id = UUID()
            guardian.studentID = try #require(student.id).uuidString
            guardian.name = name
            guardian.email = "\(name.prefix(4).lowercased())@example.com"
        }
        CoreDataTestHelpers.save(context)

        let everyone = try await call("families", ["view": "guardians"], in: tools)
        #expect(everyone.contains("Rosa Soto"))
        #expect(!everyone.contains("Dina Gold"))

        let hers = try await call("families", ["view": "guardians", "student_name": .string("Rivka Gold")], in: tools)
        #expect(hers.contains("Dina Gold"), "asking for her by name still finds her family")
    }

    // MARK: - #13: student_presentation_history

    @Test("since still numbers a repeat from the whole record")
    func historySinceKeepsTheOrdinal() async throws {
        let (tools, context) = try makeTools()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        _ = PresentationFactory.makePresented(
            lesson: lesson, students: [ora], presentedAt: try CoreDataTestHelpers.day("2026-03-02"), context: context
        )
        _ = PresentationFactory.makePresented(
            lesson: lesson, students: [ora], presentedAt: try CoreDataTestHelpers.day("2026-09-08"), context: context
        )
        CoreDataTestHelpers.save(context)

        let output = try await call("student_record", ["sections": ["presentation_history"], 
            "student_name": .string("Ora"), "since": .string("2026-09-01")
        ], in: tools)

        #expect(output.contains("2026-09-08 — Checkerboard (2nd time)"))
        #expect(!output.contains("2026-03-02"))
    }

    // MARK: - #14: the smaller items

    @Test("student_observations names the child in full")
    func observationsHeaderUsesTheFullName() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)

        let output = try await call("student_record", ["sections": ["observations"], "student_name": .string("Etty Klein")], in: tools)

        #expect(output.contains("No notes about Etty Klein"))
    }
}
