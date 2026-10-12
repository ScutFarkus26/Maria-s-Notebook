import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12, agent MC: an area answered for one lesson (#25),
// "Ungrouped" made into a real sub-area (#26), sub-areas out of album order
// (#27), unfiled lessons pushed to the end (#28) and a move that makes two
// lessons with one name in one sub-area (#2).

@Suite("MCP curriculum (Fix1012MC)")
@MainActor
struct MCPCurriculumToolsFix1012MCTests {
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

    /// The refusal's message, or a marker that the call didn't refuse.
    private func refusal(
        _ name: String, _ arguments: [String: JSONValue], in tools: [MCPToolDefinition]
    ) async -> String {
        do {
            _ = try await call(name, arguments, in: tools)
            return "no refusal"
        } catch let error as MCPToolError {
            return error.message
        } catch {
            return "unexpected: \(error)"
        }
    }

    /// A saved sub-area order for an area no other test uses, removed again
    /// by `forgetSequenceOrder` so the shared defaults stay as they were.
    private func uniqueArea(_ stem: String) -> String {
        "\(stem) \(UUID().uuidString.prefix(8))"
    }

    private func forgetSequenceOrder(for area: String) {
        UserDefaults.standard.removeObject(forKey: "Lessons.SequenceOrder." + area.normalizedForComparison())
        FilterOrderStore.resetCache()
    }

    // MARK: - #25: an exact area wins over a lesson that contains its name

    @Test("class_curriculum_map given an area answers for the area, not a lesson naming it")
    func areaBeatsPartialLessonMatch() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.seedLesson(in: context, name: "The Cell", area: "Biology", sequence: "Life")
        CoreDataTestHelpers.seedLesson(
            in: context, name: "Introduction to Biology", area: "Science", sequence: "Foundations"
        )
        #expect(CoreDataTestHelpers.save(context))

        let output = try await call("class_curriculum_map", ["lesson_or_area": .string("Biology")], in: tools)

        #expect(output.hasPrefix("Biology (best state across the area)"))
        #expect(!output.contains("Introduction to Biology"))
    }

    @Test("class_curriculum_map passes on an ambiguous lesson name instead of swallowing it")
    func ambiguousLessonIsReported() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.seedLesson(in: context, name: "Fractions: Naming", area: "Math", sequence: "Fractions")
        CoreDataTestHelpers.seedLesson(in: context, name: "Fractions: Adding", area: "Math", sequence: "Fractions")
        #expect(CoreDataTestHelpers.save(context))

        let message = await refusal("class_curriculum_map", ["lesson_or_area": .string("Fractions")], in: tools)

        #expect(message.contains("More than one lesson matches"))
    }

    @Test("class_curriculum_map still names the areas when nothing matches")
    func unknownReferenceListsAreas() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.seedLesson(in: context, name: "The Cell", area: "Biology", sequence: "Life")
        #expect(CoreDataTestHelpers.save(context))

        let message = await refusal("class_curriculum_map", ["lesson_or_area": .string("Astronomy")], in: tools)

        #expect(message.contains("is neither a lesson nor an area"))
        #expect(message.contains("Biology"))
    }

    // MARK: - #26: "Ungrouped" means no sub-area

    @Test("create_lesson with sub_area Ungrouped files the lesson with no sub-area")
    func createUngroupedFilesUnderNoSubArea() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedLesson(in: context, name: "Loose", area: "Language", sequence: "")
        CoreDataTestHelpers.seedLesson(in: context, name: "Noun", area: "Language", sequence: "Word Study")
        #expect(CoreDataTestHelpers.save(context))

        let reply = try await call("create_lesson", [
            "name": .string("Handwriting"), "area": .string("Language"), "sub_area": .string("ungrouped")
        ], in: tools)

        let lessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        let created = try #require(lessons.first { $0.name == "Handwriting" })
        #expect(created.sequence == "")
        #expect(reply.contains("Language › Ungrouped"))
        #expect(!reply.contains("new sub-area"))

        let listing = try await call("list_lessons_by_area", ["area": .string("Language")], in: tools)
        #expect(listing.components(separatedBy: "Language › Ungrouped").count == 2)
        #expect(listing.contains("Language › Ungrouped — 2 lesson(s)"))
    }

    @Test("update_lesson moving a lesson to Ungrouped clears its sub-area")
    func moveToUngroupedClearsSubArea() async throws {
        let (tools, context) = try makeTools()
        let noun = CoreDataTestHelpers.seedLesson(in: context, name: "Noun", area: "Language", sequence: "Word Study")
        #expect(CoreDataTestHelpers.save(context))

        _ = try await call("update_lesson", [
            "lesson": .string(try #require(noun.id).uuidString), "sub_area": .string("Ungrouped")
        ], in: tools)

        #expect(noun.sequence == "")
    }

    // MARK: - #2: a move never makes two lessons with one name in one sub-area

    @Test("update_lesson refuses a move into a sub-area that already has that name")
    func moveRefusesTwin() async throws {
        let (tools, context) = try makeTools()
        let moving = CoreDataTestHelpers.seedLesson(
            in: context, name: "Introduction", area: "Math", sequence: "Decimals"
        )
        CoreDataTestHelpers.seedLesson(in: context, name: "Introduction", area: "Math", sequence: "Fractions")
        #expect(CoreDataTestHelpers.save(context))

        let message = await refusal("update_lesson", [
            "lesson": .string(try #require(moving.id).uuidString), "sub_area": .string("fractions")
        ], in: tools)

        #expect(message.contains("\"Introduction\" is already in Math › Fractions. Choose a different name."))
        #expect(moving.sequence == "Decimals")
        #expect(!context.hasChanges)
    }

    @Test("update_lesson refuses a rename and move that lands on a twin")
    func renameAndMoveRefusesTwin() async throws {
        let (tools, context) = try makeTools()
        let moving = CoreDataTestHelpers.seedLesson(in: context, name: "Intro", area: "Math", sequence: "Decimals")
        CoreDataTestHelpers.seedLesson(in: context, name: "Introduction", area: "Math", sequence: "Fractions")
        #expect(CoreDataTestHelpers.save(context))

        let message = await refusal("update_lesson", [
            "lesson": .string(try #require(moving.id).uuidString),
            "name": .string("Introduction"), "sub_area": .string("Fractions")
        ], in: tools)

        #expect(message.contains("is already in Math › Fractions"))
        #expect(moving.name == "Intro")
        #expect(moving.sequence == "Decimals")
    }

    @Test("update_lesson still moves a lesson whose name is free in the new sub-area")
    func moveWithoutTwinSucceeds() async throws {
        let (tools, context) = try makeTools()
        let moving = CoreDataTestHelpers.seedLesson(
            in: context, name: "Introduction", area: "Math", sequence: "Decimals"
        )
        CoreDataTestHelpers.seedLesson(in: context, name: "Equivalence", area: "Math", sequence: "Fractions")
        #expect(CoreDataTestHelpers.save(context))

        _ = try await call("update_lesson", [
            "lesson": .string(try #require(moving.id).uuidString), "sub_area": .string("Fractions")
        ], in: tools)

        #expect(moving.sequence == "Fractions")
    }

    // MARK: - #27: student_curriculum_map reads sub-areas in album order

    @Test("student_curriculum_map lists an area's sub-areas in the saved album order")
    func studentMapUsesAlbumOrder() async throws {
        let (tools, context) = try makeTools()
        let area = uniqueArea("Geography")
        defer { forgetSequenceOrder(for: area) }
        FilterOrderStore.saveSequenceOrder(["Zones", "Atlas"], for: area)
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        CoreDataTestHelpers.seedLesson(in: context, name: "Reading an Atlas", area: area, sequence: "Atlas")
        CoreDataTestHelpers.seedLesson(in: context, name: "Climate Zones", area: area, sequence: "Zones")
        #expect(CoreDataTestHelpers.save(context))

        let output = try await call("student_curriculum_map", [
            "student_name": .string("Ora"), "granularity": .string("allLessons")
        ], in: tools)

        let zones = try #require(output.range(of: "Climate Zones"))
        let atlas = try #require(output.range(of: "Reading an Atlas"))
        #expect(zones.lowerBound < atlas.lowerBound)
    }

    // MARK: - #28: unfiled lessons keep their saved place in the area's order

    @Test("A lesson added over MCP leaves unfiled lessons where the saved order puts them")
    func unfiledLessonsKeepTheirPlace() async throws {
        let (tools, context) = try makeTools()
        let area = uniqueArea("Music")
        defer { forgetSequenceOrder(for: area) }
        FilterOrderStore.saveSequenceOrder([MCPNotebookTools.ungroupedSequenceLabel, "Bells"], for: area)
        let loose = CoreDataTestHelpers.seedLesson(in: context, name: "Listening Walk", area: area, sequence: "")
        loose.sortIndex = 0
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Matching Bells", area: area, sequence: "Bells")
        first.sortIndex = 1
        #expect(CoreDataTestHelpers.save(context))

        _ = try await call("create_lesson", [
            "name": .string("Grading Bells"), "area": .string(area), "sub_area": .string("Bells")
        ], in: tools)

        let lessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        let created = try #require(lessons.first { $0.name == "Grading Bells" })
        #expect(loose.sortIndex == 0)
        #expect(first.sortIndex == 1)
        #expect(created.sortIndex == 2)
    }

}
