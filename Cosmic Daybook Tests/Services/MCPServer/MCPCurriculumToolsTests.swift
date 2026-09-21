import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Curriculum Tools")
@MainActor
struct MCPCurriculumToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        return (tools, context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    /// Seeds a sub-area with the given names in order, numbered the way the app numbers them.
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

    private func names(in sequence: String, area: String, context: NSManagedObjectContext) -> [String] {
        MCPNotebookTools.lessonsInSequence(sequence, area: area, from: lessons(in: context)).map(\.name)
    }

    private func ids(_ lessons: [CDLesson]) -> [String] { lessons.compactMap { $0.id?.uuidString } }

    // MARK: - list_lessons_by_area

    @Test("list_lessons_by_area lists a sub-area in order with 1-based positions and no cap")
    func listSubAreaInOrderWithoutCap() async throws {
        let (tools, context) = try makeTools()
        let names = (1...30).map { "Lesson \($0)" }
        seedSequence(Array(names.reversed()), area: "Language", sequence: "Logical Analysis", in: context)
        CoreDataTestHelpers.seedLesson(in: context, name: "Other", area: "Language", sequence: "Word Study")
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "list_lessons_by_area", in: tools).handler([
            "area": .string("language"), "sub_area": .string("logical analysis")
        ])
        let lines = output.split(separator: "\n").map(String.init)
        #expect(lines.first == "Language › Logical Analysis — 30 lesson(s)")
        #expect(lines.count == 31)
        #expect(lines[1].hasPrefix("1. [lesson id="))
        #expect(lines[1].hasSuffix("Lesson 30 — Language › Logical Analysis"))
        #expect(lines[30].hasPrefix("30. "))
        #expect(lines[30].contains("Lesson 1 —"))
        #expect(!output.contains("Other"))
    }

    @Test("list_lessons_by_area groups a whole area by sub-area and refuses an unknown area")
    func listAreaGroupsBySubArea() async throws {
        let (tools, context) = try makeTools()
        seedSequence(["Noun", "Verb"], area: "Language", sequence: "Word Study", in: context)
        seedSequence(["Subject", "Predicate"], area: "Language", sequence: "Logical Analysis", in: context)
        CoreDataTestHelpers.seedLesson(in: context, name: "Loose", area: "Language", sequence: "")
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame", area: "Math", sequence: "Operations")
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "list_lessons_by_area", in: tools).handler(["area": .string("Language")])
        #expect(output.hasPrefix("Language: 5 lesson(s) in 3 sub-area(s)"))
        #expect(output.contains("Language › Logical Analysis — 2 lesson(s)\n1. [lesson id="))
        #expect(output.contains("Language › Word Study — 2 lesson(s)"))
        #expect(output.contains("Language › Ungrouped — 1 lesson(s)"))
        #expect(!output.contains("Bead Frame"))

        await #expect(throws: MCPToolError.self) {
            try await tool(named: "list_lessons_by_area", in: tools).handler(["area": .string("Astronomy")])
        }
    }

    // MARK: - create_lesson

    @Test("create_lesson appends to the sub-area, numbers it like the app, and refreshes the track")
    func createAppendsAndNumbers() async throws {
        let (tools, context) = try makeTools()
        seedSequence(["Subject", "Predicate"], area: "Language", sequence: "Logical Analysis", in: context)
        seedSequence(["Noun"], area: "Language", sequence: "Word Study", in: context)
        #expect(CoreDataTestHelpers.save(context))

        let output = try await tool(named: "create_lesson", in: tools).handler([
            "name": .string("Direct Object"), "area": .string("Language"),
            "sub_area": .string("Logical Analysis"), "write_up": .string("Introduce the black circle.")
        ])
        #expect(output.hasPrefix("Added [lesson id="))
        #expect(output.contains("position 3 of 3 in Language › Logical Analysis."))

        let all = lessons(in: context)
        #expect(all.count == 4)
        let created = try #require(all.first { $0.name == "Direct Object" })
        #expect(created.id != nil)
        #expect(created.orderInSequence == 2)
        #expect(created.writeUp == "Introduce the black circle.")
        #expect(created.source == .album)
        #expect(!created.hasChanges)
        // sortIndex is rebuilt across the whole area: one contiguous run per sub-area,
        // in whatever sub-area order this Mac's scope map has saved.
        let byName: [String: Int64] = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0.sortIndex) })
        let indices: Set<Int64> = Set(all.map(\.sortIndex))
        #expect(indices == [0, 1, 2, 3])
        let subject: Int64 = try #require(byName["Subject"])
        #expect(byName["Predicate"] == subject + 1)
        #expect(byName["Direct Object"] == subject + 2)

        let track = try SequenceTrackService.cdGetTrack(
            area: "Language", sequence: "Logical Analysis", context: context
        )
        let steps = (track?.steps?.allObjects as? [CDTrackStep]) ?? []
        #expect(steps.contains { $0.lessonTemplateID == created.id })
    }

    @Test("create_lesson places the lesson after an anchor in the same sub-area")
    func createAfterAnchor() async throws {
        let (tools, context) = try makeTools()
        let seeded = seedSequence(
            ["Subject", "Predicate", "Object"], area: "Language", sequence: "Logical Analysis", in: context
        )
        #expect(CoreDataTestHelpers.save(context))
        let anchorID = try #require(seeded[0].id).uuidString

        let output = try await tool(named: "create_lesson", in: tools).handler([
            "name": .string("Verb"), "area": .string("Language"),
            "sub_area": .string("Logical Analysis"), "after_lesson": .string(anchorID)
        ])
        #expect(output.contains("position 2 of 4"))
        #expect(names(in: "Logical Analysis", area: "Language", context: context)
                == ["Subject", "Verb", "Predicate", "Object"])

        await #expect(throws: MCPToolError.self) {
            try await tool(named: "create_lesson", in: tools).handler([
                "name": .string("Adverb"), "area": .string("Language"),
                "sub_area": .string("Word Study"), "after_lesson": .string(anchorID)
            ])
        }
        #expect(lessons(in: context).count == 4)
    }

    @Test("create_lesson is idempotent on name within a sub-area and deletes nothing")
    func createIsIdempotent() async throws {
        let (tools, context) = try makeTools()
        let seeded = seedSequence(
            ["Subject", "Prédicate"], area: "Language", sequence: "Logical Analysis", in: context
        )
        #expect(CoreDataTestHelpers.save(context))
        let existingID = try #require(seeded[1].id).uuidString
        let before = Set(ids(lessons(in: context)))

        let output = try await tool(named: "create_lesson", in: tools).handler([
            "name": .string("  predicate "), "area": .string("language"), "sub_area": .string("LOGICAL ANALYSIS")
        ])
        #expect(output.hasPrefix("Already in the curriculum, nothing added: [lesson id=\(existingID)]"))
        #expect(output.contains("position 2 of 2"))
        #expect(Set(ids(lessons(in: context))) == before)

        // The same name under a different sub-area is a different lesson.
        _ = try await tool(named: "create_lesson", in: tools).handler([
            "name": .string("Predicate"), "area": .string("Language"), "sub_area": .string("Word Study")
        ])
        #expect(lessons(in: context).count == 3)
    }

    @Test("create_lesson creates a sub-area under an existing area but never a new area")
    func createRefusesNewAreaAndListsExisting() async throws {
        let (tools, context) = try makeTools()
        seedSequence(["Subject"], area: "Language", sequence: "Logical Analysis", in: context)
        CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame", area: "Math", sequence: "Operations")
        #expect(CoreDataTestHelpers.save(context))

        let refusal = await #expect(throws: MCPToolError.self) {
            try await tool(named: "create_lesson", in: tools).handler([
                "name": .string("Stars"), "area": .string("Astronomy"), "sub_area": .string("Sky")
            ])
        }
        let message = try #require(refusal?.message)
        #expect(message.contains("Existing areas:") && message.contains("Language") && message.contains("Math"))
        #expect(lessons(in: context).count == 2)

        let output = try await tool(named: "create_lesson", in: tools).handler([
            "name": .string("Noun"), "area": .string("Language"), "sub_area": .string("Word Study")
        ])
        #expect(output.contains("Language › Word Study (new sub-area)"))
        #expect(Set(MCPNotebookTools.orderedSequences(inArea: "Language", from: lessons(in: context)))
                == ["Logical Analysis", "Word Study"])
    }

    // MARK: - update_lesson

    @Test("update_lesson renames without breaking a presentation that references the lesson")
    func updateRenamesSafely() async throws {
        let (tools, context) = try makeTools()
        let seeded = seedSequence(["Subject", "Predicate"], area: "Language", sequence: "Logical Analysis", in: context)
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let planned = PresentationFactory.makeScheduled(
            lesson: seeded[0], students: [ora], scheduledFor: Date(), context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        let lessonID = try #require(seeded[0].id)

        let output = try await tool(named: "update_lesson", in: tools).handler([
            "lesson": .string(lessonID.uuidString), "name": .string("Subject and Predicate"),
            "teacher_notes": .string("Give with the symbols out.")
        ])
        #expect(output.contains("renamed \"Subject\" to \"Subject and Predicate\""))
        #expect(output.contains("teacher notes"))
        #expect(seeded[0].name == "Subject and Predicate")
        #expect(seeded[0].teacherNotes == "Give with the symbols out.")
        #expect(planned.lessonIDUUID == lessonID)
        #expect(planned.lesson?.name == "Subject and Predicate")
        #expect(lessons(in: context).count == 2)

        await #expect(throws: MCPToolError.self) {
            try await tool(named: "update_lesson", in: tools).handler([
                "lesson": .string(lessonID.uuidString), "name": .string("predicate")
            ])
        }
        await #expect(throws: MCPToolError.self) {
            try await tool(named: "update_lesson", in: tools).handler(["lesson": .string(lessonID.uuidString)])
        }
    }

    @Test("update_lesson moves a lesson to the end of another sub-area and refuses a new area")
    func updateMovesSubArea() async throws {
        let (tools, context) = try makeTools()
        let seeded = seedSequence(["Subject", "Predicate"], area: "Language", sequence: "Logical Analysis", in: context)
        seedSequence(["Noun", "Verb"], area: "Language", sequence: "Word Study", in: context)
        #expect(CoreDataTestHelpers.save(context))
        let subjectID = try #require(seeded[0].id).uuidString

        let output = try await tool(named: "update_lesson", in: tools).handler([
            "lesson": .string(subjectID), "sub_area": .string("word study")
        ])
        #expect(output.contains("moved from Language › Logical Analysis to Language › Word Study (end)"))
        #expect(names(in: "Word Study", area: "Language", context: context) == ["Noun", "Verb", "Subject"])
        #expect(names(in: "Logical Analysis", area: "Language", context: context) == ["Predicate"])
        #expect(seeded[0].sequence == "Word Study")
        #expect(seeded[0].orderInSequence == 2)

        await #expect(throws: MCPToolError.self) {
            try await tool(named: "update_lesson", in: tools).handler([
                "lesson": .string(subjectID), "area": .string("Astronomy"), "sub_area": .string("Sky")
            ])
        }
        #expect(seeded[0].area == "Language")
        #expect(lessons(in: context).count == 4)
    }

    // MARK: - reorder_lessons

    @Test("reorder_lessons applies a partial order and carries unlisted lessons after it")
    func reorderKeepsUnlistedLessons() async throws {
        let (tools, context) = try makeTools()
        let seeded = seedSequence(["A", "B", "C", "D", "E"], area: "Math", sequence: "Fractions", in: context)
        seedSequence(["Bead Frame"], area: "Math", sequence: "Operations", in: context)
        #expect(CoreDataTestHelpers.save(context))
        let before = Set(ids(lessons(in: context)))
        let idOf: (Int) throws -> JSONValue = { index in
            let id: UUID = try #require(seeded[index].id)
            return JSONValue.string(id.uuidString)
        }

        let output = try await tool(named: "reorder_lessons", in: tools).handler([
            "area": .string("Math"), "sub_area": .string("Fractions"),
            "lesson_ids": .array([try idOf(4), try idOf(2), try idOf(0)])
        ])
        #expect(output.hasPrefix("Math › Fractions now runs (2 unlisted lesson(s) kept their order after them):"))
        let lines: [String] = output.split(separator: "\n").dropFirst().map(String.init)
        let markers: [String] = lines.map { String($0.prefix(2)) }
        #expect(markers == ["1.", "2.", "3.", "4.", "5."])
        #expect(names(in: "Fractions", area: "Math", context: context) == ["E", "C", "A", "B", "D"])
        let orders: [Int64] = seeded.map(\.orderInSequence)
        #expect(orders == [2, 3, 1, 4, 0])
        #expect(Set(ids(lessons(in: context))) == before)
        #expect(lessons(in: context).allSatisfy { !$0.hasChanges })
    }

    @Test("reorder_lessons refuses a lesson from another sub-area, a duplicate, and an empty list")
    func reorderRefusesForeignLessons() async throws {
        let (tools, context) = try makeTools()
        let fractions = seedSequence(["A", "B"], area: "Math", sequence: "Fractions", in: context)
        let operations = seedSequence(["Bead Frame"], area: "Math", sequence: "Operations", in: context)
        #expect(CoreDataTestHelpers.save(context))
        let a = try #require(fractions[0].id).uuidString
        let foreign = try #require(operations[0].id).uuidString

        let refusal = await #expect(throws: MCPToolError.self) {
            try await tool(named: "reorder_lessons", in: tools).handler([
                "area": .string("Math"), "sub_area": .string("Fractions"),
                "lesson_ids": .array([.string(foreign), .string(a)])
            ])
        }
        #expect(refusal?.message.contains("is not in Math › Fractions") == true)
        await #expect(throws: MCPToolError.self) {
            try await tool(named: "reorder_lessons", in: tools).handler([
                "area": .string("Math"), "sub_area": .string("Fractions"),
                "lesson_ids": .array([.string(a), .string(a)])
            ])
        }
        await #expect(throws: MCPToolError.self) {
            try await tool(named: "reorder_lessons", in: tools).handler([
                "area": .string("Math"), "sub_area": .string("Fractions"), "lesson_ids": .array([])
            ])
        }
        #expect(names(in: "Fractions", area: "Math", context: context) == ["A", "B"])
        #expect(operations[0].sequence == "Operations")
    }

    // MARK: - Store routing

    @Test("create_lesson lands in the private store like an in-app add, ready for the classroom share")
    func createRoutesToPrivateStore() async throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let tools = MCPNotebookTools.makeTools(context: { context })
        CoreDataTestHelpers.seedLesson(in: context, name: "Subject", area: "Language", sequence: "Logical Analysis")
        #expect(CoreDataTestHelpers.save(context))

        _ = try await tool(named: "create_lesson", in: tools).handler([
            "name": .string("Predicate"), "area": .string("Language"), "sub_area": .string("Logical Analysis")
        ])
        let created = try #require(lessons(in: context).first { $0.name == "Predicate" })
        #expect(created.objectID.persistentStore?.configurationName == CoreDataStack.privateConfiguration)
    }
}
