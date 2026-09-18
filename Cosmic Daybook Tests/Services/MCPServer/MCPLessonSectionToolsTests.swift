import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The lesson `section` over MCP: `create_lesson` and `update_lesson` store it,
/// and `list_lessons_by_area` is the one read that shows it — banded under
/// section headings the way the scope map and the Checklist draw a sub-area.
@Suite("MCP Lesson Section Tools")
@MainActor
struct MCPLessonSectionToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        return (tools, context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    @discardableResult
    private func seedSequence(
        _ names: [String], area: String, sequence: String, in context: NSManagedObjectContext
    ) -> [CDLesson] {
        names.enumerated().map { index, name in
            let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name, area: area, sequence: sequence)
            lesson.orderInSequence = Int64(index)
            return lesson
        }
    }

    private func lessons(in context: NSManagedObjectContext) -> [CDLesson] {
        context.safeFetch(CDFetchRequest(CDLesson.self))
    }

    // MARK: - list_lessons_by_area

    @Test("list_lessons_by_area bands a sub-area under its section headings without renumbering it")
    func listSubAreaUnderSectionHeadings() async throws {
        let (tools, context) = try makeTools()
        let seeded = seedSequence(
            ["By 2", "By 5", "By 3", "Prime Factors"], area: "Math", sequence: "Divisibility Drills", in: context
        )
        seeded[0].section = "Group 1"
        seeded[1].section = "Group 1"
        seeded[2].section = "Group 2"
        seedSequence(["Bead Frame"], area: "Math", sequence: "Operations", in: context)
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "list_lessons_by_area", in: tools).handler([
            "area": .string("Math"), "sub_area": .string("Divisibility Drills")
        ])
        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines.first == "Math › Divisibility Drills — 4 lesson(s)")
        #expect(lines.count == 8)
        #expect(lines[1] == "Section: Group 1")
        #expect(lines[2].hasPrefix("1. [lesson id=") && lines[2].contains("By 2 —"))
        #expect(lines[3].hasPrefix("2. ") && lines[3].contains("By 5 —"))
        #expect(lines[4] == "Section: Group 2")
        #expect(lines[5].hasPrefix("3. ") && lines[5].contains("By 3 —"))
        #expect(lines[6] == "No section")
        #expect(lines[7].hasPrefix("4. ") && lines[7].contains("Prime Factors —"))

        // A sub-area with no sections keeps the plain list, and the area listing bands too.
        let area = try await tool(named: "list_lessons_by_area", in: tools).handler(["area": .string("Math")])
        #expect(area.contains("Math › Operations — 1 lesson(s)\n1. [lesson id="))
        #expect(area.contains("Math › Divisibility Drills — 4 lesson(s)\nSection: Group 1\n1. "))
        #expect(!area.contains("Operations — 1 lesson(s)\nNo section"))
    }

    // MARK: - create_lesson

    @Test("create_lesson stores the section it is given and the listing shows it")
    func createPersistsSection() async throws {
        let (tools, context) = try makeTools()
        seedSequence(["Subject"], area: "Language", sequence: "Logical Analysis", in: context)
        #expect(CoreDataTestHelpers.save(context))

        _ = try await tool(named: "create_lesson", in: tools).handler([
            "name": .string("Predicate"), "area": .string("Language"),
            "sub_area": .string("Logical Analysis"), "section": .string(" First Presentations ")
        ])
        let created = try #require(lessons(in: context).first { $0.name == "Predicate" })
        #expect(created.section == "First Presentations")
        #expect(!created.hasChanges)

        let output = try await tool(named: "list_lessons_by_area", in: tools).handler([
            "area": .string("Language"), "sub_area": .string("Logical Analysis")
        ])
        #expect(output.contains("Section: First Presentations\n2. [lesson id=\(created.id?.uuidString ?? "")]"))
        #expect(output.contains("No section\n1. [lesson id="))
    }

    // MARK: - update_lesson

    @Test("update_lesson sets, changes and clears the section on its own, and names it in the summary")
    func updateSectionRoundTrip() async throws {
        let (tools, context) = try makeTools()
        let seeded = seedSequence(["By 2", "By 5"], area: "Math", sequence: "Divisibility", in: context)
        seeded[0].teacherNotes = "Rule to elicit."
        #expect(CoreDataTestHelpers.save(context))
        let lessonID = try #require(seeded[0].id).uuidString
        let update = try tool(named: "update_lesson", in: tools)
        let listing = try tool(named: "list_lessons_by_area", in: tools)
        let subArea: [String: JSONValue] = ["area": .string("Math"), "sub_area": .string("Divisibility")]

        let set = try await update.handler(["lesson": .string(lessonID), "section": .string("Group 1")])
        #expect(set.hasSuffix("By 2 — Math › Divisibility: section Group 1."))
        #expect(seeded[0].section == "Group 1")
        #expect(!seeded[0].hasChanges)
        #expect(try await listing.handler(subArea).contains("Section: Group 1\n1. [lesson id=\(lessonID)]"))

        // The same value again is a no-op, reported the way every other unchanged field is.
        let unchanged = await #expect(throws: MCPToolError.self) {
            try await update.handler(["lesson": .string(lessonID), "section": .string(" Group 1 ")])
        }
        #expect(unchanged?.message.hasPrefix("Nothing to change") == true)

        let changed = try await update.handler(["lesson": .string(lessonID), "section": .string("Group 2")])
        #expect(changed.hasSuffix(": section Group 2."))
        #expect(seeded[0].section == "Group 2")
        #expect(try await listing.handler(subArea).contains("Section: Group 2\n1. "))

        let cleared = try await update.handler(["lesson": .string(lessonID), "section": .string("")])
        #expect(cleared.hasSuffix(": cleared section."))
        #expect(seeded[0].section == "")
        let plain = try await listing.handler(subArea)
        #expect(!plain.contains("Section:") && plain.contains("1. [lesson id=\(lessonID)]"))

        // Section alongside another field: both are applied and both are named.
        let both = try await update.handler([
            "lesson": .string(lessonID), "section": .string("Group 1"), "teacher_notes": .string("New rule.")
        ])
        #expect(both.hasSuffix(": section Group 1; teacher notes."))
        #expect(seeded[0].section == "Group 1" && seeded[0].teacherNotes == "New rule.")
        #expect(seeded[0].name == "By 2" && seeded[1].section == "")
    }
}
