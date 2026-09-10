import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("MCP Curriculum Map Tools")
@MainActor
struct MCPCurriculumMapToolsTests {
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

    /// Ora: started 2025-11-29; the Commutative Law presented and chosen, the
    /// Distributive Law (a key lesson) not yet, Biology never touched.
    private struct Classroom {
        let student: CDStudent
        let commutative: CDLesson
        let distributive: CDLesson
        let cells: CDLesson
    }

    private func seedClassroom(in context: NSManagedObjectContext) throws -> Classroom {
        let student = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Ora", lastName: "Pardo", level: .upper, dateStarted: day("2025-11-29")
        )
        let commutative = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Commutative Law of Multiplication", area: "Math", sequence: "Laws"
        )
        commutative.orderInSequence = 0
        let distributive = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Distributive Law of Multiplication", area: "Math", sequence: "Laws"
        )
        distributive.orderInSequence = 1
        distributive.isKeyLesson = true
        let subStep = CoreDataTestHelpers.seedLesson(in: context, name: "A sub-step", area: "Math", sequence: "Laws")
        subStep.orderInSequence = 2
        let cells = CoreDataTestHelpers.seedLesson(in: context, name: "The Cell", area: "Biology", sequence: "Life")
        cells.orderInSequence = 0

        let studentID = try #require(student.id)
        let presentation = PresentationFactory.makeDraft(lesson: commutative, students: [student], context: context)
        presentation.markPresented(at: day("2026-02-12"))
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Commutative practice", studentID: studentID, lessonID: try #require(commutative.id)
        )
        work.assignedAt = day("2026-02-13")
        #expect(CoreDataTestHelpers.save(context))
        return Classroom(student: student, commutative: commutative, distributive: distributive, cells: cells)
    }

    // MARK: - student_curriculum_map

    @Test("student_curriculum_map reports each key lesson's state and the untouched areas")
    func studentMapReportsStatesAndUntouched() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)

        let output = try await tool(named: "student_curriculum_map", in: tools).handler([
            "student_name": .string("Ora")
        ])
        #expect(output.contains("Ora Pardo — Year 1 (started 2025-11-29)"))
        #expect(output.contains("Great Lessons:"))
        #expect(output.contains("Coming of the Universe: no lesson tagged"))
        #expect(output.contains("Math: 1 of 3 presented; last presentation 2026-02-12"))
        #expect(output.contains("The Commutative Law of Multiplication (Laws) — chosen; presented 2026-02-12; 1 work"))
        #expect(output.contains("The Distributive Law of Multiplication (Laws) — notPresented"))
        #expect(!output.contains("A sub-step"))
        #expect(output.contains("Biology: 0 of 1 presented"))
        #expect(output.contains("Untouched areas"))
        #expect(output.contains("Biology (never presented; flagged after 90 days)"))
    }

    @Test("granularity area collapses to one line per area; allLessons shows every sub-step")
    func granularityChangesTheRows() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)
        let map = try tool(named: "student_curriculum_map", in: tools)

        let areas = try await map.handler(["student_name": .string("Ora"), "granularity": .string("area")])
        #expect(areas.contains("Math: 1 of 3 presented"))
        #expect(!areas.contains("[lesson id="))

        let all = try await map.handler(["student_name": .string("Ora"), "granularity": .string("allLessons")])
        #expect(all.contains("A sub-step (Laws) — notPresented"))
    }

    @Test("since keeps only lessons with activity on or after the day")
    func sinceFiltersLessons() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)
        let map = try tool(named: "student_curriculum_map", in: tools)

        let recent = try await map.handler(["student_name": .string("Ora"), "since": .string("2026-03-01")])
        #expect(!recent.contains("The Commutative Law of Multiplication (Laws)"))
        #expect(recent.contains("(nothing since 2026-03-01)"))

        await #expect(throws: MCPToolError.self) {
            try await map.handler(["student_name": .string("Ora"), "since": .string("yesterday")])
        }
    }

    // MARK: - class_curriculum_map

    @Test("class_curriculum_map groups the class by state on one lesson")
    func classMapGroupsByState() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Dalia", lastName: "Singer", dateStarted: day("2024-09-01"))
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "class_curriculum_map", in: tools).handler([
            "lesson_or_area": .string("The Distributive Law of Multiplication")
        ])
        #expect(output.contains("2 enrolled child(ren)"))
        #expect(output.contains("Not yet presented (2):"))
        #expect(output.contains("Dalia Singer (Year 3)"))
        #expect(output.contains("Ora Pardo (Year 1)"))
        #expect(output.contains("Mastered (0):\n  none"))
        // Oldest cohort first.
        let dalia = try #require(output.range(of: "Dalia Singer"))
        let ora = try #require(output.range(of: "Ora Pardo"))
        #expect(dalia.lowerBound < ora.lowerBound)
    }

    @Test("class_curriculum_map takes an area and a state filter")
    func classMapByArea() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)
        let map = try tool(named: "class_curriculum_map", in: tools)

        let math = try await map.handler(["lesson_or_area": .string("math")])
        #expect(math.contains("Math (best state across the area)"))
        #expect(math.contains("Chosen (1):"))
        #expect(math.contains("Ora Pardo (Year 1, last presentation 2026-02-12)"))

        let filtered = try await map.handler(["lesson_or_area": .string("Biology"), "state": .string("notPresented")])
        #expect(filtered.contains("Not yet presented (1):"))
        #expect(!filtered.contains("Mastered"))

        await #expect(throws: MCPToolError.self) {
            try await map.handler(["lesson_or_area": .string("Astronomy")])
        }
    }

    @Test("Key lessons are marked in lesson citations")
    func keyLessonShowsInCitations() async throws {
        let (tools, context) = try makeTools()
        _ = try seedClassroom(in: context)

        let output = try await tool(named: "find_lessons", in: tools).handler(["query": .string("Distributive")])
        #expect(output.contains("The Distributive Law of Multiplication — Math › Laws (key lesson)"))

        let updated = try await tool(named: "update_lesson", in: tools).handler([
            "lesson": .string("The Distributive Law of Multiplication"), "is_key_lesson": .bool(false)
        ])
        #expect(updated.contains("no longer a key lesson"))
    }
}
