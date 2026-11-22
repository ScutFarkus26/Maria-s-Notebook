import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("MCP Classroom Tools")
@MainActor
struct MCPClassroomToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    // MARK: - Supplies

    @Test("adjust_supply logs a transaction alongside the new count")
    func adjustSupplyWritesTransaction() async throws {
        let (tools, context) = try makeTools()
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = "Golden Beads"
        supply.categoryRaw = "Math"
        supply.currentQuantity = 20
        CoreDataTestHelpers.save(context)

        let receipt = try await tool(named: "adjust_supply", in: tools).handler([
            "supply": .string("Golden Beads"),
            "change": .int(-8),
            "reason": .string("Used in a lesson")
        ])
        #expect(receipt.contains("now 12"))
        #expect(supply.currentQuantity == 12)

        let transactions = context.safeFetch(CDFetchRequest(CDSupplyTransaction.self))
        #expect(transactions.count == 1)
        #expect(transactions.first?.quantityChange == -8)
    }

    @Test("adjust_supply refuses to drive stock negative")
    func adjustSupplyRefusesNegativeStock() async throws {
        let (tools, context) = try makeTools()
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = "Pencils"
        supply.categoryRaw = "Office"
        supply.currentQuantity = 3
        CoreDataTestHelpers.save(context)

        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "adjust_supply", in: tools).handler([
                "supply": .string("Pencils"),
                "change": .int(-10)
            ])
        }
        #expect(supply.currentQuantity == 3)
    }

    @Test("adjust_supply set_to computes the difference from the counted total")
    func adjustSupplySetToComputesDelta() async throws {
        let (tools, context) = try makeTools()
        let supply = CDSupply(context: context)
        supply.id = UUID()
        supply.name = "Sandpaper Letters"
        supply.categoryRaw = "Language"
        supply.currentQuantity = 10
        CoreDataTestHelpers.save(context)

        _ = try await tool(named: "adjust_supply", in: tools).handler([
            "supply": .string("Sandpaper Letters"),
            "set_to": .int(14),
            "reason": .string("Recounted")
        ])
        #expect(supply.currentQuantity == 14)
        let transaction = try #require(context.safeFetch(CDFetchRequest(CDSupplyTransaction.self)).first)
        #expect(transaction.quantityChange == 4)
    }
}
