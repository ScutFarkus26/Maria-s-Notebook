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
        #expect(names.count == 83)
        #expect(Set(names).count == names.count)

        let encoder = JSONEncoder()
        for tool in tools {
            #expect(!tool.title.isEmpty && !tool.description.isEmpty, "\(tool.name) needs a title and description")
            #expect(throws: Never.self, "\(tool.name)'s schema must encode") {
                _ = try encoder.encode(tool.inputSchema)
            }
        }

        let added: Set<String> = [
            "list_lessons_by_area", "create_lesson", "update_lesson", "reorder_lessons",
            "discard_presentation", "update_presentation_roster", "clear_year_plan",
            "student_curriculum_map", "class_curriculum_map", "students_pending",
            "students_ready", "mastery_candidates"
        ]
        #expect(added.isSubset(of: Set(names)))
    }

    /// Every tool that changes the notebook. Pinned literally so a tool that
    /// quietly starts writing — or a write that is mislabelled read-only —
    /// is a red test rather than a silently softened permission prompt.
    private static let writingTools: Set<String> = [
        // creates
        "add_follow_up", "add_project_session", "adjust_supply", "assign_work",
        "create_lesson", "create_meeting_entry", "create_observation",
        "record_parent_communication", "record_presentation", "schedule_meeting",
        "schedule_presentation",
        // edits in place
        "assign_job", "day_pad", "mark_attendance", "mark_mastered", "reorder_lessons",
        "reschedule_presentation", "resolve_follow_up", "update_community_topic",
        "update_going_out", "update_guardian", "update_issue", "update_lesson",
        "update_observation", "update_presentation_roster", "update_project",
        "update_student", "update_todo", "update_work", "update_year_plan_entry",
        // deletes and retirements
        "clear_year_plan", "discard_presentation", "remove_student_from_work",
        "skip_year_plan_entries",
        "create_backup", "draft_parent_report"
    ]

    /// The tools that delete or retire rows.
    private static let destructiveTools: Set<String> = [
        "clear_year_plan", "discard_presentation", "remove_student_from_work",
        "skip_year_plan_entries"
    ]

    @Test("Annotations classify every tool, and nothing reaches outside the notebook")
    func annotationsClassifyEveryTool() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })

        let writing = Set(tools.filter { !$0.annotations.readOnlyHint }.map(\.name))
        #expect(writing == Self.writingTools)

        let destructive = Set(tools.filter(\.annotations.destructiveHint).map(\.name))
        #expect(destructive == Self.destructiveTools)
        #expect(Self.destructiveTools.isSubset(of: Self.writingTools))

        for tool in tools {
            #expect(!tool.annotations.openWorldHint, "\(tool.name) only reads the local notebook")
            if tool.annotations.readOnlyHint {
                #expect(tool.annotations.idempotentHint, "\(tool.name) reads, so it is idempotent")
                #expect(!tool.annotations.destructiveHint, "\(tool.name) reads, so it destroys nothing")
            }
        }
    }
}
