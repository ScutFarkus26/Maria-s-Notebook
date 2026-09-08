import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("MCP Family Tools")
@MainActor
struct MCPFamilyToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    // MARK: - Guardians

    @Test("update_guardian adds a guardian and list_guardians reports them")
    func updateGuardianAddsAndLists() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "update_guardian", in: tools).handler([
            "student_name": .string("Maya"),
            "name": .string("Rosa Soto"),
            "email": .string("rosa@example.com"),
            "relationship": .string("mother"),
            "receives_reports": .bool(true)
        ])
        #expect(receipt.contains("Added"))

        let listed = try await tool(named: "list_guardians", in: tools).handler([
            "student_name": .string("Maya")
        ])
        #expect(listed.contains("Rosa Soto"))
        #expect(listed.contains("rosa@example.com"))
        #expect(listed.contains("receives reports"))
    }

    @Test("update_guardian needs a student when adding")
    func updateGuardianNeedsStudentWhenAdding() async throws {
        let (tools, _) = try makeTools()
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_guardian", in: tools).handler([
                "name": .string("Someone")
            ])
        }
    }

    @Test("list_guardians can narrow to those who receive reports")
    func listGuardiansFiltersByReportFlag() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Ross")
        CoreDataTestHelpers.save(context)

        let updateTool = try tool(named: "update_guardian", in: tools)
        _ = try await updateTool.handler([
            "student_name": .string("Eli"),
            "name": .string("Dana Ross"),
            "receives_reports": .bool(true)
        ])
        _ = try await updateTool.handler([
            "student_name": .string("Eli"),
            "name": .string("Chris Ross"),
            "receives_reports": .bool(false)
        ])

        let filtered = try await tool(named: "list_guardians", in: tools).handler([
            "receives_reports_only": .bool(true)
        ])
        #expect(filtered.contains("Dana Ross"))
        #expect(!filtered.contains("Chris Ross"))
    }

    // MARK: - Communications

    @Test("record_parent_communication files a draft without sending it")
    func recordCommunicationFilesDraft() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "Perez")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "record_parent_communication", in: tools).handler([
            "student_name": .string("Ana"),
            "subject": .string("September report"),
            "body": .string("Ana has settled into the decimal work."),
            "type": .string("monthlyReport"),
            "month": .string("2026-09")
        ])

        let communication = try #require(
            context.safeFetch(CDFetchRequest(CDParentCommunication.self)).first
        )
        #expect(communication.status == .draft)
        // Filing must never look like sending — nothing leaves the app here.
        #expect(communication.sentAt == nil)
    }

    @Test("record_parent_communication stamps the sent date when marked sent")
    func recordCommunicationStampsSentDate() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Sam", lastName: "Lee")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "record_parent_communication", in: tools).handler([
            "student_name": .string("Sam"),
            "subject": .string("Conference notes")
        ])
        let communication = try #require(
            context.safeFetch(CDFetchRequest(CDParentCommunication.self)).first
        )
        let id = try #require(communication.id).uuidString

        _ = try await tool(named: "record_parent_communication", in: tools).handler([
            "communication_id": .string(id),
            "status": .string("sent"),
            "sent_date": .string("2026-09-14")
        ])
        #expect(communication.status == .sent)
        let expected = try #require(MCPNotebookTools.isoDay.date(from: "2026-09-14"))
        #expect(communication.sentAt == expected)
    }

    // MARK: - Todos

    @Test("list_todos narrows to a student and hides completed items by default")
    func listTodosFiltersByStudentAndStatus() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Rae", lastName: "Kim")
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Jon", lastName: "Alvarez")
        CoreDataTestHelpers.save(context)

        let addTool = try tool(named: "add_follow_up", in: tools)
        _ = try await addTool.handler([
            "title": .string("Call Rae's family"),
            "student_names": .array([.string("Rae")])
        ])
        _ = try await addTool.handler([
            "title": .string("Order Jon's materials"),
            "student_names": .array([.string("Jon")])
        ])

        let forRae = try await tool(named: "list_todos", in: tools).handler([
            "student_name": .string("Rae")
        ])
        #expect(forRae.contains("Call Rae's family"))
        #expect(!forRae.contains("Order Jon's materials"))
    }

    @Test("update_todo rewrites the student list and refuses an empty change")
    func updateTodoRewritesStudents() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ivy", lastName: "Chen")
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "add_follow_up", in: tools).handler([
            "title": .string("Find a bird guide")
        ])
        let todo = try #require(context.safeFetch(CDFetchRequest(CDTodoItem.self)).first)
        let id = try #require(todo.id).uuidString

        _ = try await tool(named: "update_todo", in: tools).handler([
            "todo_id": .string(id),
            "student_names": .array([.string("Ivy")])
        ])
        #expect(todo.studentIDsArray.count == 1)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_todo", in: tools).handler(["todo_id": .string(id)])
        }
    }
}
