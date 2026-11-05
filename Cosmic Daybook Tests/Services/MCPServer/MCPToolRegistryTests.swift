import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Tool Registry")
@MainActor
struct MCPToolRegistryTests {

    @Test("Every tool has a unique name and a schema that serialises for tools/list")
    func registryIsWellFormed() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })

        let names: [String] = tools.map(\.name)
        #expect(names.count == Self.expectedTools.count)
        #expect(Set(names).count == names.count)
        #expect((58...64).contains(names.count), "round-two Simplify, Phase 6: about 60 tools, not 97")
        #expect(Set(names) == Set(Self.expectedTools))
        // A retired name is answered, never listed.
        #expect(Set(names).isDisjoint(with: MCPNotebookTools.retiredTools.keys))

        let encoder = JSONEncoder()
        for tool in tools {
            #expect(!tool.title.isEmpty && !tool.description.isEmpty, "\(tool.name) needs a title and description")
            #expect(throws: Never.self, "\(tool.name)'s schema must encode") {
                _ = try encoder.encode(tool.inputSchema)
            }
        }
    }

    /// One line per tool the server lists. A tool added, removed or renamed is a red test
    /// here, and the same edit to docs/Technical notes/MCP_SERVER.md.
    private static let expectedTools: [String] = [
        // roster, notebook, lessons, albums
        "list_students", "update_student", "search_notebook", "notebook_status", "data_checks",
        "find_lessons", "create_lesson", "update_lesson", "reorder_lessons",
        "attach_file_to_lesson", "list_lesson_attachments", "remove_lesson_attachment",
        "albums", "list_templates",
        // a child, the class, the plan
        "student_record", "class_curriculum_map", "class_progress",
        "year_plan", "update_year_plan_entry", "skip_year_plan_entries", "clear_year_plan",
        // schedules and presentations
        "weekly_schedules", "set_timetable", "change_schedule_day", "schedule_for_range",
        "schedule_presentation", "reschedule_presentation", "discard_presentation",
        "update_presentation_roster", "record_presentation", "mark_mastered",
        // observations and meetings
        "create_observation", "update_observation", "create_meeting_entry", "schedule_meeting",
        // work
        "work_detail", "assign_work", "update_work", "remove_student_from_work",
        // attendance, to-dos, follow-ups
        "attendance_for_day", "mark_attendance", "send_attendance_to_school",
        "list_todos", "add_follow_up", "update_todo", "resolve_follow_up",
        // families
        "families", "update_guardian", "record_parent_communication",
        // classroom
        "list_supplies", "adjust_supply", "mark_supplies", "list_projects",
        "list_issues", "update_issue", "community_topics", "update_community_topic",
        "list_resources", "day_pad",
        // school calendar and the app
        "school_calendar", "set_school_days", "update_school_calendar",
        "create_backup", "draft_parent_report"
    ]

    @Test("Every retired tool name answers with one plain sentence saying where it went")
    func retiredNamesAnswer() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let handler = MCPRequestHandler(
            serverVersion: "1.0-test", tools: MCPNotebookTools.makeTools(context: { context })
        )
        let table = MCPNotebookTools.retiredTools
        #expect(table.count == 38)
        for (name, sentence) in table.sorted(by: { $0.key < $1.key }) {
            let request = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(name)","arguments":{}}}"#
            let reply = try #require(await handler.handle(line: Data(request.utf8)))
            let object = try #require(try JSONDecoder().decode(JSONValue.self, from: reply).objectValue)
            let result = try #require(object["result"]?.objectValue, "\(name) answers as a tool result")
            #expect(result["isError"]?.boolValue == true)
            let text = try #require(result["content"]?.arrayValue?.first?.objectValue?["text"]?.stringValue)
            #expect(text == sentence)
            #expect(text.hasPrefix(name), "\(name)'s answer starts with its own name")
            #expect(!text.contains("\n"), "\(name)'s answer is one sentence")
        }
        // A name that never existed is still an unknown tool.
        let unknown = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"no_such_tool","arguments":{}}}"#
        let reply = try #require(await handler.handle(line: Data(unknown.utf8)))
        let object = try #require(try JSONDecoder().decode(JSONValue.self, from: reply).objectValue)
        #expect(object["error"] != nil)
    }

    @Test("A retired name that says it moved names a tool the server lists")
    func retiredNamesPointAtRealHomes() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let homes = Set(MCPNotebookTools.makeTools(context: { context }).map(\.name))
        for (name, sentence) in MCPNotebookTools.retiredTools where sentence.contains(" moved into ") {
            let afterMoved = try #require(sentence.components(separatedBy: " moved into ").last, "\(name)")
            let home = try #require(afterMoved.components(separatedBy: ";").first, "\(name)")
            #expect(homes.contains(home), "\(name) says it moved into \(home), which isn't listed")
        }
    }

    @Test("No listed tool's text sends Claude to a retired name")
    func listedToolsNameNoRetiredTool() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })
        // A retired name that is now a view or section of its new home (say
        // "mastery_candidates") may still be named as that value.
        let values = MCPNotebookTools.retiredTools.values.flatMap { sentence in
            sentence.matches(of: /(?:view|sections): \[?"([a-z_]+)"/).map { String($0.output.1) }
        }
        // record_presentation's `student_observations` argument is not the old tool.
        let retired = Set(MCPNotebookTools.retiredTools.keys).subtracting(values)
            .subtracting(["student_observations"])
        let encoder = JSONEncoder()
        for tool in tools {
            let schema = String(decoding: try encoder.encode(tool.inputSchema), as: UTF8.self)
            let words = Set((tool.description + " " + schema)
                .split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "_") })
                .map(String.init))
            let named = words.intersection(retired)
            #expect(named.isEmpty, "\(tool.name) still names \(named.sorted())")
        }
    }

    /// Every tool that changes the notebook. Pinned literally so a tool that
    /// quietly starts writing — or a write that is mislabelled read-only —
    /// is a red test rather than a silently softened permission prompt.
    private static let writingTools: Set<String> = [
        // creates
        "add_follow_up", "adjust_supply", "assign_work",
        "create_lesson", "create_meeting_entry", "create_observation",
        "record_parent_communication", "record_presentation", "schedule_meeting",
        "schedule_presentation",
        // edits in place
        "day_pad", "mark_attendance", "mark_mastered", "reorder_lessons",
        "reschedule_presentation", "resolve_follow_up", "update_community_topic",
        "update_guardian", "update_issue", "update_lesson",
        "update_observation", "update_presentation_roster",
        "update_student", "update_todo", "update_work", "update_year_plan_entry",
        "set_school_days", "update_school_calendar", "change_schedule_day",
        "mark_supplies", "attach_file_to_lesson",
        // deletes and retirements
        "clear_year_plan", "discard_presentation", "remove_student_from_work",
        "skip_year_plan_entries", "set_timetable", "remove_lesson_attachment",
        "create_backup", "draft_parent_report",
        // sends outside the notebook
        "send_attendance_to_school"
    ]

    /// The tools that delete or retire rows.
    private static let destructiveTools: Set<String> = [
        "clear_year_plan", "discard_presentation", "remove_student_from_work",
        "skip_year_plan_entries", "set_timetable", "remove_lesson_attachment"
    ]

    /// The tools that reach outside the notebook: only the send to the
    /// school's ParentLocker site (plan "ParentLocker attendance").
    private static let openWorldTools: Set<String> = ["send_attendance_to_school"]

    @Test("Annotations classify every tool, and only the school send reaches outside the notebook")
    func annotationsClassifyEveryTool() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })

        let writing = Set(tools.filter { !$0.annotations.readOnlyHint }.map(\.name))
        #expect(writing == Self.writingTools)

        let destructive = Set(tools.filter(\.annotations.destructiveHint).map(\.name))
        #expect(destructive == Self.destructiveTools)
        #expect(Self.destructiveTools.isSubset(of: Self.writingTools))

        let openWorld = Set(tools.filter(\.annotations.openWorldHint).map(\.name))
        #expect(openWorld == Self.openWorldTools)
        #expect(Self.openWorldTools.isSubset(of: Self.writingTools))

        for tool in tools where tool.annotations.readOnlyHint {
            #expect(tool.annotations.idempotentHint, "\(tool.name) reads, so it is idempotent")
            #expect(!tool.annotations.destructiveHint, "\(tool.name) reads, so it destroys nothing")
        }
    }

    /// Round-two Simplify, Phase 4: note templates were retired, so
    /// `list_templates` no longer offers or lists them, even when a store
    /// still holds the old rows.
    @Test("list_templates has no note kind and lists no note templates")
    func listTemplatesHasNoNoteKind() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let entity = try #require(context.persistentStoreCoordinator?.managedObjectModel.entitiesByName["NoteTemplate"])
        let old = NSManagedObject(entity: entity, insertInto: context)
        old.setValue(UUID(), forKey: "id")
        old.setValue("Observation", forKey: "title")
        #expect(CoreDataTestHelpers.save(context))
        let tools = MCPNotebookTools.makeTools(context: { context })
        let tool = try #require(tools.first { $0.name == "list_templates" })

        let schema = try #require(String(data: JSONEncoder().encode(tool.inputSchema), encoding: .utf8))
        #expect(!schema.contains("\"note\""))
        #expect(!tool.description.localizedCaseInsensitiveContains("note"))
        let all = try await tool.handler([:])
        #expect(!all.contains("Note templates") && !all.contains("noteTemplate"))
        let noteKind = try await tool.handler(["kind": .string("note")])
        #expect(noteKind == "No templates are set up.")
    }
}
