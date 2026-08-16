import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("MCP Notebook Tools")
@MainActor
struct MCPNotebookToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        return (tools, context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    @Test("list_students lists enrolled students with ids")
    func listStudentsListsSeededStudents() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "list_students", in: tools).handler([:])
        #expect(output.contains("Ada Lovelace"))
        let id = try #require(student.id?.uuidString)
        #expect(output.contains(id))
    }

    @Test("create_observation writes a scoped, linked note")
    func createObservationWritesNote() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maria", lastName: "Montessori")
        CoreDataTestHelpers.save(context)
        let studentID = try #require(student.id)

        let output = try await tool(named: "create_observation", in: tools).handler([
            "student_names": .array([.string("Maria")]),
            "body": .string("Chose the golden beads and worked independently."),
            "needs_follow_up": .bool(true)
        ])
        #expect(output.contains("Maria Montessori"))

        let notes = context.safeFetch(CDFetchRequest(CDNote.self))
        #expect(notes.count == 1)
        let note = try #require(notes.first)
        #expect(note.body == "Chose the golden beads and worked independently.")
        #expect(note.needsFollowUp)
        #expect(note.scope == .student(studentID))
    }

    @Test("create_observation rejects unknown students without saving")
    func createObservationRejectsUnknownStudent() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maria", lastName: "Montessori")
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "create_observation", in: tools).handler([
                "student_names": .array([.string("Nobody")]),
                "body": .string("This should not be saved.")
            ])
        }
        #expect(context.safeFetch(CDFetchRequest(CDNote.self)).isEmpty)
    }

    @Test("Ambiguous student names ask for clarification")
    func ambiguousNamesAskForClarification() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maria", lastName: "Montessori")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maria", lastName: "Curie")
        CoreDataTestHelpers.save(context)

        do {
            _ = try await tool(named: "student_observations", in: tools).handler([
                "student_name": .string("Maria")
            ])
            Issue.record("Expected an ambiguity error")
        } catch let error as MCPToolError {
            #expect(error.message.contains("More than one student"))
            #expect(error.message.contains("Maria Curie"))
        }
    }

    @Test("update_student sets a nickname by name and clears it with an empty string")
    func updateStudentSetsAndClearsNickname() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maria", lastName: "Montessori")
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "update_student", in: tools).handler([
            "student": .string("Maria"),
            "nickname": .string("Mimi")
        ])
        #expect(output.contains("nickname → \"Mimi\""))
        #expect(student.nickname == "Mimi")

        let cleared = try await tool(named: "update_student", in: tools).handler([
            "student": .string("Maria"),
            "nickname": .string("")
        ])
        #expect(cleared.contains("cleared nickname"))
        #expect(student.nickname == nil)
    }

    @Test("update_student accepts a student id and multiple fields")
    func updateStudentAcceptsIDReference() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        CoreDataTestHelpers.save(context)
        let id = try #require(student.id?.uuidString)

        let output = try await tool(named: "update_student", in: tools).handler([
            "student": .string(id),
            "level": .string("upper"),
            "birthday": .string("2017-03-09")
        ])
        #expect(output.contains("level → upper"))
        #expect(student.level == .upper)
        let birthday = try #require(student.birthday)
        #expect(MCPNotebookTools.isoDay.string(from: birthday) == "2017-03-09")
    }

    @Test("update_student accepts the adolescent level")
    func updateStudentAcceptsAdolescentLevel() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Zakon")
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "update_student", in: tools).handler([
            "student": .string("Sarah"),
            "level": .string("adolescent")
        ])
        #expect(output.contains("level → adolescent"))
        #expect(student.level == .adolescent)
        #expect(student.previousLevel == .lower, "a level change records the prior level")
    }

    @Test("update_student with no changes is an error")
    func updateStudentRequiresChanges() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maria", lastName: "Montessori")
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_student", in: tools).handler([
                "student": .string("Maria")
            ])
        }
    }

    @Test("update_observation edits body and follow-up flag by id")
    func updateObservationEditsNote() async throws {
        let (tools, context) = try makeTools()
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Original text.")
        CoreDataTestHelpers.save(context)
        let id = try #require(note.id?.uuidString)

        let output = try await tool(named: "update_observation", in: tools).handler([
            "note_id": .string(id),
            "body": .string("Revised text."),
            "needs_follow_up": .bool(true)
        ])
        #expect(output.contains("body"))
        #expect(note.body == "Revised text.")
        #expect(note.needsFollowUp)
    }

    @Test("update_observation rejects unknown note ids")
    func updateObservationRejectsUnknownID() async throws {
        let (tools, _) = try makeTools()
        do {
            _ = try await tool(named: "update_observation", in: tools).handler([
                "note_id": .string(UUID().uuidString),
                "body": .string("Anything")
            ])
            Issue.record("Expected an unknown-id error")
        } catch let error as MCPToolError {
            #expect(error.message.contains("was found") || error.message.contains("No observation"))
        }
    }

    @Test("student_observations returns scoped notes only")
    func studentObservationsReturnsScopedNotes() async throws {
        let (tools, context) = try makeTools()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        let studentID = try #require(student.id)
        let scoped = CoreDataTestHelpers.seedNote(in: context, body: "Worked with the stamp game.")
        scoped.scope = .student(studentID)
        let classroomWide = CoreDataTestHelpers.seedNote(in: context, body: "Whole class went out to the garden.")
        classroomWide.scope = .all
        CoreDataTestHelpers.save(context)

        let output = try await tool(named: "student_observations", in: tools).handler([
            "student_name": .string("Ada")
        ])
        #expect(output.contains("stamp game"))
        #expect(!output.contains("garden"))
    }
}
