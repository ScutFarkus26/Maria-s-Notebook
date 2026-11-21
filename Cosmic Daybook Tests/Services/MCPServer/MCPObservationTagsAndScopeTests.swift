// MCPObservationTagsAndScopeTests.swift
// Domain logic review 2026-11-20, A10 and A20: Claude's note tags take the
// stored form of a tag the notebook already has (its color included), and an
// empty children list on a presentation's note keeps the presentation's
// children, as the note editor does, instead of widening it to the class.

import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP observation tags and scope (domain logic A10, A20)")
@MainActor
struct MCPObservationTagsAndScopeTests {

    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(_ name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    @Test("create_observation files a tag under the color the notebook already gives it")
    func createKeepsStoredColor() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela")
        let tagged = CoreDataTestHelpers.seedNote(in: context, body: "Earlier note.")
        tagged.tagsArray = [TagHelper.createTag(name: "Social", color: .purple)]
        #expect(CoreDataTestHelpers.save(context))

        _ = try await tool("create_observation", in: tools).handler([
            "student_names": .array([.string("Maya")]),
            "body": .string("Invited a younger child to join."),
            "tags": .array([.string("social"), .string("Grace & Courtesy")])
        ])

        let note = try #require(context.safeFetch(CDFetchRequest(CDNote.self)).first { $0.body.hasPrefix("Invited") })
        #expect(note.tagsArray.contains("Social|Purple"))
        #expect(note.tagsArray.contains(MontessoriObservationTags.graceAndCourtesy))
        #expect(!note.tagsArray.contains("social"))
    }

    @Test("The stored tags are read on a SQLite store too")
    func vocabularyOnSQLite() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let tagged = CoreDataTestHelpers.seedNote(in: context, body: "Earlier note.")
        tagged.tagsArray = [TagHelper.createTag(name: "Social", color: .purple)]
        try context.save()
        context.refreshAllObjects()

        let vocabulary = TagHelper.noteTagVocabulary(in: context)
        #expect(vocabulary.contains("Social|Purple"))
        #expect(TagHelper.canonicalTags(["social"], existing: vocabulary) == ["Social|Purple"])
    }

    @Test("update_observation's tags take the stored color too")
    func updateKeepsStoredColor() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela")
        let tagged = CoreDataTestHelpers.seedNote(in: context, body: "Earlier note.")
        tagged.tagsArray = [TagHelper.createTag(name: "Focus", color: .blue)]
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Worked an hour.")
        note.scope = .student(try #require(maya.id))
        #expect(CoreDataTestHelpers.save(context))

        _ = try await tool("update_observation", in: tools).handler([
            "note_id": .string(try #require(note.id).uuidString),
            "tags": .array([.string("Focus"), .string("Brand new")])
        ])

        #expect(note.tagsArray == ["Focus|Blue", "Brand new|Gray"])
    }

    @Test("An empty children list on a presentation's note keeps the presentation's children")
    func emptyListKeepsPresentationRoster() async throws {
        let (tools, context) = try makeTools()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sela")
        let leo = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leo", lastName: "Katz")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let mayaID = try #require(maya.id)
        let leoID = try #require(leo.id)
        let presentation = CDLessonAssignment(context: context)
        presentation.lessonID = try #require(lesson.id).uuidString
        presentation.studentIDs = [mayaID.uuidString, leoID.uuidString]
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Both traced the sandpaper letters.")
        note.scope = .student(mayaID)
        note.lessonAssignment = presentation
        #expect(CoreDataTestHelpers.save(context))

        _ = try await tool("update_observation", in: tools).handler([
            "note_id": .string(try #require(note.id).uuidString),
            "student_names": .array([])
        ])

        #expect(note.scope != .all, "not widened to the whole class")
        #expect(Set(note.scope.studentIDs ?? []) == [mayaID, leoID])
    }
}
