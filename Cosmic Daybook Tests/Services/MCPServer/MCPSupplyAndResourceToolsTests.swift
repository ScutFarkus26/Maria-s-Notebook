import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `list_supplies` and `list_resources` printing each row once.
///
/// The live notebook held three supplies and answered with six lines, two
/// resources and answered with six — the same id repeated, because the shelf was
/// cloned between the private and shared stores and an unscoped fetch
/// legitimately sees both copies. The launch-time cleanup now folds them, but
/// the readers fold too: they must be right on the run *before* the cleanup has
/// happened, and scoping the fetch to one store instead would return nothing at
/// all on an assistant's device, where these rows live only in the shared store.
@Suite("MCP Supply And Resource Tools")
@MainActor
struct MCPSupplyAndResourceToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    @Test("Two copies of one supply are listed once")
    func suppliesAreFoldedByID() async throws {
        let (tools, context) = try makeTools()
        let sharedID = UUID()
        for offset in 0..<2 {
            let supply = CDSupply(context: context)
            supply.id = sharedID
            supply.name = "Golden Beads"
            supply.location = "Math shelf"
            supply.currentQuantity = 40
            supply.createdAt = Date(timeIntervalSince1970: TimeInterval(1_000 + offset))
        }
        #expect(CoreDataTestHelpers.save(context))

        let listing = try await tool(named: "list_supplies", in: tools).handler([:])
        #expect(listing.hasPrefix("1 supply/supplies"))
        #expect(occurrences(of: "Golden Beads", in: listing) == 1)
    }

    @Test("A cloned supply can still be adjusted by name")
    func adjustResolvesACloneWithoutAmbiguity() async throws {
        let (tools, context) = try makeTools()
        let sharedID = UUID()
        for offset in 0..<2 {
            let supply = CDSupply(context: context)
            supply.id = sharedID
            supply.name = "Pencils"
            supply.currentQuantity = 100
            supply.createdAt = Date(timeIntervalSince1970: TimeInterval(1_000 + offset))
        }
        #expect(CoreDataTestHelpers.save(context))

        // Before the fold, both copies matched the name and the tool refused
        // with "more than one supply is called that".
        let receipt = try await tool(named: "adjust_supply", in: tools).handler([
            "supply": .string("Pencils"),
            "change": .int(-10),
            "reason": .string("Used in a lesson")
        ])
        #expect(receipt.contains("now 90"))
    }

    @Test("Three copies of one resource are listed once")
    func resourcesAreFoldedByID() async throws {
        let (tools, context) = try makeTools()
        let sharedID = UUID()
        for offset in 0..<3 {
            let resource = CDResource(context: context)
            resource.id = sharedID
            resource.title = "Timeline of Life"
            resource.createdAt = Date(timeIntervalSince1970: TimeInterval(1_000 + offset))
        }
        #expect(CoreDataTestHelpers.save(context))

        let listing = try await tool(named: "list_resources", in: tools).handler([:])
        #expect(occurrences(of: "Timeline of Life", in: listing) == 1)
    }

    @Test("Two genuinely different supplies are both still listed")
    func distinctSuppliesSurvive() async throws {
        let (tools, context) = try makeTools()
        for name in ["Bead Bars", "Sandpaper Letters"] {
            let supply = CDSupply(context: context)
            supply.id = UUID()
            supply.name = name
            supply.currentQuantity = 5
            supply.createdAt = Date()
        }
        #expect(CoreDataTestHelpers.save(context))

        let listing = try await tool(named: "list_supplies", in: tools).handler([:])
        #expect(listing.hasPrefix("2 supply/supplies"))
    }
}
