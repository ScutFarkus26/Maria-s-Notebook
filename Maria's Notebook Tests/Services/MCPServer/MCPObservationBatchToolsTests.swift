import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// `create_observation`'s duplicate guard and its batch form. The matching
/// guard on `add_follow_up` has its own suite.
@Suite("MCP Observation Batch And Duplicate Guard")
@MainActor
struct MCPObservationBatchToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func notes(in context: NSManagedObjectContext) -> [CDNote] {
        context.safeFetch(CDFetchRequest(CDNote.self))
    }

    private func item(
        students: [String], body: String, date: String? = nil
    ) -> JSONValue {
        var fields: [String: JSONValue] = [
            "student_names": .array(students.map { .string($0) }),
            "body": .string(body)
        ]
        if let date {
            fields["date"] = .string(date)
        }
        return .object(fields)
    }

    // MARK: - create_observation Guard

    @Test("create_observation reports an identical note from that day and files nothing")
    func duplicateObservationIsReported() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let create = try tool(named: "create_observation", in: tools)

        let arguments: [String: JSONValue] = [
            "student_names": .array([.string("Ora")]),
            "body": .string("  Chose the checkerboard on her own.  "),
            "date": .string("2026-09-14")
        ]
        _ = try await create.handler(arguments)
        let filed = try #require(notes(in: context).first)
        let id = try #require(filed.id).uuidString

        let second = try await create.handler(arguments)
        #expect(second.contains("already exists"))
        #expect(second.contains("[note id=\(id)]"))
        #expect(second.contains("force: true"))
        #expect(second.contains("2026-09-14"))
        #expect(notes(in: context).count == 1)
        // The guard reads only: the note it found is untouched.
        #expect(filed.isDeleted == false)
        #expect(filed.body.contains("checkerboard"))
    }

    @Test("create_observation with force files the second copy anyway")
    func forceBypassesObservationGuard() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let create = try tool(named: "create_observation", in: tools)

        let arguments: [String: JSONValue] = [
            "student_names": .array([.string("Ora")]),
            "body": .string("Chose the checkerboard on her own."),
            "date": .string("2026-09-14")
        ]
        _ = try await create.handler(arguments)
        var forced = arguments
        forced["force"] = .bool(true)
        let receipt = try await create.handler(forced)

        #expect(receipt.contains("Recorded observation"))
        #expect(notes(in: context).count == 2)
    }

    @Test("the same words about a different child, or on a different day, are not duplicates")
    func guardComparesScopeAndDay() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)
        let create = try tool(named: "create_observation", in: tools)

        _ = try await create.handler([
            "student_names": .array([.string("Ora")]),
            "body": .string("Read aloud to the younger children."),
            "date": .string("2026-09-14")
        ])
        _ = try await create.handler([
            "student_names": .array([.string("Etty")]),
            "body": .string("Read aloud to the younger children."),
            "date": .string("2026-09-14")
        ])
        _ = try await create.handler([
            "student_names": .array([.string("Ora")]),
            "body": .string("Read aloud to the younger children."),
            "date": .string("2026-09-15")
        ])
        #expect(notes(in: context).count == 3)
    }

    @Test("the single form still files one note and cites it")
    func singleFormStillWorks() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "create_observation", in: tools).handler([
            "student_names": .array([.string("Ora")]),
            "body": .string("Built the binomial cube unprompted."),
            "date": .string("2026-09-14"),
            "tags": .array([.string("math")]),
            "needs_follow_up": .bool(true)
        ])
        let note = try #require(notes(in: context).first)
        let id = try #require(note.id).uuidString
        #expect(receipt == "Recorded observation [note id=\(id)] about Ora Levi on 2026-09-14.")
        #expect(note.tagsArray == ["math"])
        #expect(note.needsFollowUp)
    }

    // MARK: - create_observation Batch

    @Test("a batch resolves every item before writing and files them in one save")
    func batchFilesEveryItem() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "create_observation", in: tools).handler([
            "notes": .array([
                item(students: ["Ora"], body: "Sorted the leaf cabinet.", date: "2026-09-14"),
                item(students: ["Etty", "Ora"], body: "Worked together on the map.",
                     date: "2026-09-14")
            ])
        ])
        #expect(receipt.contains("Filed 2 observation(s):"))
        #expect(receipt.contains("for Ora Levi on 2026-09-14"))
        #expect(receipt.contains("for Etty Klein, Ora Levi on 2026-09-14"))
        #expect(receipt.components(separatedBy: "- Filed [note id=").count == 3)
        #expect(notes(in: context).count == 2)
    }

    @Test("one bad name fails the whole batch, naming the item, and writes nothing")
    func batchIsAllOrNothing() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)

        do {
            _ = try await tool(named: "create_observation", in: tools).handler([
                "notes": .array([
                    item(students: ["Ora"], body: "Sorted the leaf cabinet."),
                    item(students: ["Ora"], body: "Read to the younger children."),
                    item(students: ["Zeta"], body: "Traced the sandpaper letters.")
                ])
            ])
            Issue.record("Expected the batch to be refused.")
        } catch let error as MCPToolError {
            #expect(error.message.contains("notes[2]"))
            #expect(error.message.contains("Traced the sandpaper letters."))
            #expect(error.message.contains("Zeta"))
        }
        #expect(notes(in: context).isEmpty)
    }

    @Test("a duplicate item in a batch is skipped and cited, not an error")
    func batchSkipsDuplicates() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let create = try tool(named: "create_observation", in: tools)

        _ = try await create.handler([
            "student_names": .array([.string("Ora")]),
            "body": .string("Sorted the leaf cabinet."),
            "date": .string("2026-09-14")
        ])
        let filed = try #require(notes(in: context).first)
        let existing = try #require(filed.id).uuidString

        let receipt = try await create.handler([
            "notes": .array([
                item(students: ["Ora"], body: "Sorted the leaf cabinet.", date: "2026-09-14"),
                item(students: ["Ora"], body: "Read to the younger children.", date: "2026-09-14")
            ])
        ])
        #expect(receipt.contains("Filed 1 observation(s), skipped 1 duplicate(s):"))
        #expect(receipt.contains("- Skipped: identical note exists [note id=\(existing)]"))
        #expect(notes(in: context).count == 2)
    }

    @Test("force in a batch applies to every item")
    func batchForceAppliesThroughout() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(context)
        let create = try tool(named: "create_observation", in: tools)

        _ = try await create.handler([
            "student_names": .array([.string("Ora")]),
            "body": .string("Sorted the leaf cabinet."),
            "date": .string("2026-09-14")
        ])
        let receipt = try await create.handler([
            "force": .bool(true),
            "notes": .array([
                item(students: ["Ora"], body: "Sorted the leaf cabinet.", date: "2026-09-14")
            ])
        ])
        #expect(receipt.contains("Filed 1 observation(s):"))
        #expect(notes(in: context).count == 2)
    }
}
