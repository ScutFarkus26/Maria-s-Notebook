import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP App Service Tools")
@MainActor
struct MCPAppServiceToolsTests {
    private struct Harness {
        let tools: [MCPToolDefinition]
        let context: NSManagedObjectContext
        let dependencies: AppDependencies
    }

    private func makeHarness() throws -> Harness {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let dependencies = AppDependencies(coreDataStack: stack)
        let tools = MCPNotebookTools.makeTools(context: { context }, dependencies: { dependencies })
        return Harness(tools: tools, context: context, dependencies: dependencies)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    // MARK: - Registration

    @Test("the app-service tool is registered, and draft_parent_report is gone")
    func toolsAreRegistered() throws {
        let harness = try makeHarness()
        let names = Set(harness.tools.map(\.name))
        #expect(names.contains("create_backup"))
        #expect(!names.contains("draft_parent_report"))
    }

    @Test("without a registered container the tool says the app is still starting")
    func toolsRefuseWithoutDependencies() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        let tools = MCPNotebookTools.makeTools(context: { context }, dependencies: { nil })

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "create_backup", in: tools).handler([:])
        }
    }

    // MARK: - create_backup

    @Test("create_backup writes an archive and reports its path")
    func createBackupWritesAnArchive() async throws {
        let harness = try makeHarness()
        CoreDataTestHelpers.seedStudent(in: harness.context, firstName: "Ora", lastName: "Levi")
        CoreDataTestHelpers.save(harness.context)

        let output = try await tool(named: "create_backup", in: harness.tools).handler([:])
        #expect(output.hasPrefix("Backup written "))
        let marker = "[backup path="
        let start = try #require(output.range(of: marker)?.upperBound)
        let end = try #require(output[start...].firstIndex(of: "]"))
        let path = String(output[start..<end])
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(path.contains("ManualBackup-"))
        try? FileManager.default.removeItem(atPath: path)
    }
}
