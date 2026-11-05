import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Round-two Simplify, Phase 6: `student_record` and the tools with a `view`
/// stand in for the tools that were merged into them. The merged tools' own
/// behavior is tested in their moved suites; these pin the seams.
@Suite("MCP Combined Tools")
@MainActor
struct MCPCombinedToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    // MARK: - student_record

    @Test("student_record with one section returns just that section; with several, each under its name")
    func sectionsAreHeadedOnlyWhenThereIsMoreThanOne() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)
        let record = try tool(named: "student_record", in: tools)

        let one = try await record.handler(["student_name": "Maya", "sections": ["work"]])
        #expect(one == "Maya Soto has no open work.")

        let two = try await record.handler(["student_name": "Maya", "sections": ["work", "tracks", "work"]])
        #expect(two.contains("## work\nMaya Soto has no open work."))
        #expect(two.contains("## tracks\nMaya Soto has not started any lesson sequences."))
        #expect(two.components(separatedBy: "## work").count == 2, "a section named twice is returned once")
        #expect(try #require(two.range(of: "## work")).lowerBound < #require(two.range(of: "## tracks")).lowerBound)
    }

    @Test("student_record refuses a missing or unknown section and names the ones it has")
    func badSectionsAreRefused() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)
        let record = try tool(named: "student_record", in: tools)

        for arguments: [String: JSONValue] in [
            ["student_name": "Maya"],
            ["student_name": "Maya", "sections": []],
            ["student_name": "Maya", "sections": ["birthdays"]]
        ] {
            do {
                _ = try await record.handler(arguments)
                Issue.record("expected a refusal for \(arguments)")
            } catch let error as MCPToolError {
                #expect(error.message.contains("attendance, curriculum_map, meetings, observations"))
            }
        }
        await #expect(throws: MCPToolError.self) {
            _ = try await record.handler(["sections": ["work"]])
        }
    }

    @Test("student_record lists every section in its schema and needs a name and sections")
    func schemaListsEverySection() throws {
        let (tools, _) = try makeTools()
        let record = try tool(named: "student_record", in: tools)
        let schema = try #require(record.inputSchema.objectValue)
        let required = (schema["required"]?.arrayValue ?? []).compactMap(\.stringValue)
        #expect(Set(required) == ["student_name", "sections"])
        let items = try #require(schema["properties"]?.objectValue?["sections"]?.objectValue?["items"]?.objectValue)
        let listed = (items["enum"]?.arrayValue ?? []).compactMap(\.stringValue)
        #expect(listed == MCPNotebookTools.StudentRecordSection.allCases.map(\.rawValue))
        #expect(listed.count == 7)
        #expect(record.annotations == .readOnly)
    }

    // MARK: - Tools with a view

    @Test("A tool with a view names the views it has when none or a wrong one is asked for")
    func viewIsRequiredWhereThereIsNoDefault() async throws {
        let (tools, _) = try makeTools()
        for name in ["class_progress", "albums", "families", "notebook_status"] {
            let combined = try tool(named: name, in: tools)
            for arguments: [String: JSONValue] in [[:], ["view": "nonsense"]] {
                do {
                    _ = try await combined.handler(arguments)
                    Issue.record("\(name) should refuse \(arguments)")
                } catch let error as MCPToolError {
                    #expect(error.message.hasPrefix("Pass view: one of "), "\(name)")
                }
            }
            #expect(combined.annotations == .readOnly)
            let required = (combined.inputSchema.objectValue?["required"]?.arrayValue ?? []).compactMap(\.stringValue)
            #expect(required == ["view"], "\(name)")
        }
    }

    @Test("A tool with a default view answers a call without one, and offers the other view")
    func defaultViewAnswersWithoutView() async throws {
        let (tools, context) = try makeTools()
        CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        CoreDataTestHelpers.save(context)

        let roster = try await tool(named: "list_students", in: tools).handler([:])
        #expect(roster.contains("Maya Soto"))
        let snapshot = try await tool(named: "list_students", in: tools).handler(["view": "snapshot"])
        #expect(snapshot.contains("=== CLASSROOM SNAPSHOT ==="))

        let todos = try tool(named: "list_todos", in: tools)
        let views = try #require(todos.inputSchema.objectValue?["properties"]?.objectValue?["view"]?.objectValue)
        #expect((views["enum"]?.arrayValue ?? []).compactMap(\.stringValue) == ["todos", "open_follow_ups"])
        #expect((todos.inputSchema.objectValue?["required"]) == nil)
        let open = try await todos.handler(["view": "open_follow_ups"])
        #expect(!open.isEmpty)
    }

    @Test("A property two views read keeps both wordings")
    func sharedPropertiesKeepEveryViewsWording() throws {
        let (tools, _) = try makeTools()
        let albums = try tool(named: "albums", in: tools)
        let limit = try #require(albums.inputSchema.objectValue?["properties"]?.objectValue?["limit"]?.objectValue)
        let wording = try #require(limit["description"]?.stringValue)
        #expect(wording.contains("search:") && wording.contains("marks:"))
    }

    // MARK: - find_lessons and Restock

    @Test("find_lessons needs a query or an area")
    func findLessonsNeedsQueryOrArea() async throws {
        let (tools, _) = try makeTools()
        let find = try tool(named: "find_lessons", in: tools)
        await #expect(throws: MCPToolError.self) { _ = try await find.handler([:]) }
        let required = find.inputSchema.objectValue?["required"]
        #expect(required == nil)
    }

    @Test("mark_supplies takes one of supplies, new_needs or needs per call")
    func markSuppliesRefusesMixedCalls() async throws {
        let (tools, _) = try makeTools()
        let mark = try tool(named: "mark_supplies", in: tools)
        do {
            _ = try await mark.handler([
                "supplies": [["supply": "Tape", "level": "low"]],
                "new_needs": [["title": "Glue"]]
            ])
            Issue.record("a mixed call should be refused")
        } catch let error as MCPToolError {
            #expect(error.message.contains("only one of supplies, new_needs or needs"))
        }
        await #expect(throws: MCPToolError.self) { _ = try await mark.handler([:]) }
    }

    @Test("list_supplies with a stage lists needs, not staples")
    func listSuppliesWithAStageListsNeeds() async throws {
        let (tools, context) = try makeTools()
        let author = RestockAuthor(role: .leadGuide)
        _ = RestockService.addStaple(.init(name: "Paper Towels"), level: .out, by: author, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let list = try tool(named: "list_supplies", in: tools)

        let staples = try await list.handler([:])
        #expect(staples.contains("supply/supplies"))
        let needs = try await list.handler(["stage": "open"])
        #expect(needs.contains("Requests go to:"))
        #expect(needs.contains("office run (1)") || needs.contains("to order, to_request (1)"))
    }
}
