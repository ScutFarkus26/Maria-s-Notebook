import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

@Suite("MCP Tool Registry")
@MainActor
struct MCPToolRegistryTests {

    @Test("Every tool has a unique name and a schema that serialises for tools/list")
    func registryIsWellFormed() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context })

        let names: [String] = tools.map(\.name)
        #expect(names.count == 78)
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
            "student_curriculum_map", "class_curriculum_map", "students_pending"
        ]
        #expect(added.isSubset(of: Set(names)))
    }
}
