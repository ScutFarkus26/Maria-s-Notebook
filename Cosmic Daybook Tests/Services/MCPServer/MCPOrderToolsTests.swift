import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `list_orders`, `add_order_items` and `update_order_items` drive the same
/// `OrderService` calls as the Orders screen, so an item added over MCP moves
/// through the stages exactly as one dropped into the app.
@Suite("MCP Order Tools")
@MainActor
struct MCPOrderToolsTests {
    private func makeTools() throws -> (tools: [MCPToolDefinition], context: NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        return (MCPNotebookTools.makeTools(context: { context }), context)
    }

    private func tool(named name: String, in tools: [MCPToolDefinition]) throws -> MCPToolDefinition {
        try #require(tools.first { $0.name == name })
    }

    private func items(in context: NSManagedObjectContext) -> [CDOrderItem] {
        context.safeFetch(CDFetchRequest(CDOrderItem.self))
    }

    @Test("Adding reports a link already on the list instead of filing it twice")
    func addDeduplicates() async throws {
        let (tools, context) = try makeTools()
        let add = try tool(named: "add_order_items", in: tools)

        let receipt = try await add.handler([
            "items": .array([
                .object(["url": .string("example.com/pencils"), "title": .string("Pencils"), "quantity": .int(3)]),
                .object(["url": .string("https://example.com/pencils")])
            ])
        ])
        #expect(receipt.contains("Added 1 to_request"))
        #expect(receipt.contains("Already on the list"))

        let saved = items(in: context)
        #expect(saved.count == 1)
        #expect(saved.first?.title == "Pencils")
        #expect(saved.first?.quantity == 3)
    }

    @Test("A bad link anywhere in the batch adds nothing")
    func addIsAllOrNothing() async throws {
        let (tools, context) = try makeTools()
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "add_order_items", in: tools).handler([
                "items": .array([
                    .object(["url": .string("example.com/ok")]),
                    .object(["url": .string("not a link")])
                ])
            ])
        }
        #expect(items(in: context).isEmpty)
    }

    @Test("Stages move through update_order_items and read back through list_orders")
    func stagesRoundTrip() async throws {
        let (tools, context) = try makeTools()
        _ = try await tool(named: "add_order_items", in: tools).handler([
            "items": .array([
                .object(["url": .string("example.com/a"), "title": .string("Alpha")]),
                .object(["url": .string("example.com/b"), "title": .string("Beta")])
            ])
        ])
        let ids = items(in: context).compactMap { $0.id?.uuidString }
        // A fetch has no inherent order, so find Alpha by name rather than position.
        let alphaID = try #require(items(in: context).first { $0.title == "Alpha" }?.id?.uuidString)
        let update = try tool(named: "update_order_items", in: tools)

        _ = try await update.handler([
            "items": .array(ids.map { .object(["id": .string($0), "stage": .string("asked_for")]) })
        ])
        let asked = items(in: context)
        #expect(asked.allSatisfy { $0.stage == .requested })
        #expect(Set(asked.compactMap(\.requestID)).count == 1, "one call is one request")

        _ = try await update.handler([
            "items": .array([.object(["id": .string(alphaID), "stage": .string("received"), "quantity": .int(2)])])
        ])
        let alpha = try #require(items(in: context).first { $0.id?.uuidString == alphaID })
        #expect(alpha.stage == .received)
        #expect(alpha.quantity == 2)

        let open = try await tool(named: "list_orders", in: tools).handler([:])
        #expect(open.contains("asked_for (1)"))
        #expect(!open.contains("Alpha"), "open leaves out what has arrived")

        let received = try await tool(named: "list_orders", in: tools).handler(["stage": .string("received")])
        #expect(received.contains("[order id=\(alphaID)] Alpha"))
    }

    @Test("An unknown id changes nothing")
    func updateRefusesUnknownIDs() async throws {
        let (tools, context) = try makeTools()
        _ = try await tool(named: "add_order_items", in: tools).handler([
            "items": .array([.object(["url": .string("example.com/a")])])
        ])
        let id = try #require(items(in: context).first?.id?.uuidString)
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_order_items", in: tools).handler([
                "items": .array([
                    .object(["id": .string(id), "stage": .string("received")]),
                    .object(["id": .string(UUID().uuidString), "stage": .string("received")])
                ])
            ])
        }
        #expect(items(in: context).first?.stage == .toRequest)
    }

    @Test("Confirming an item never asked for is refused, and nothing in the batch changes")
    func confirmNeedsARequest() async throws {
        let (tools, context) = try makeTools()
        _ = try await tool(named: "add_order_items", in: tools).handler([
            "items": .array([.object(["url": .string("example.com/a"), "title": .string("Alpha")])])
        ])
        let id = try #require(items(in: context).first?.id?.uuidString)
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "update_order_items", in: tools).handler([
                "items": .array([.object(["id": .string(id), "stage": .string("confirmed")])])
            ])
        }
        #expect(items(in: context).first?.stage == .toRequest)
    }

    @Test("A title with no link is added as an office need, and a repeat is not added twice")
    func addTitleOnlyFromTheOffice() async throws {
        let (tools, context) = try makeTools()
        let add = try tool(named: "add_order_items", in: tools)

        let receipt = try await add.handler(["items": .array([.object(["title": .string("Tape")])])])
        #expect(receipt.contains("Added 1 to_request"))
        let saved = try #require(items(in: context).first)
        #expect(saved.source == .office)
        #expect(saved.urlString.isEmpty)

        let repeated = try await add.handler(["items": .array([.object(["title": .string("tape")])])])
        #expect(repeated.contains("Already on the list"))
        #expect(items(in: context).count == 1)

        let ordered = try await add.handler([
            "items": .array([.object(["title": .string("Easel"), "source": .string("order")])])
        ])
        #expect(ordered.contains("Added 1"))
        #expect(items(in: context).first { $0.title == "Easel" }?.source == .order)
    }

    @Test("An entry with neither link nor title adds nothing")
    func addNeedsLinkOrTitle() async throws {
        let (tools, context) = try makeTools()
        await #expect(throws: MCPToolError.self) {
            _ = try await tool(named: "add_order_items", in: tools).handler([
                "items": .array([
                    .object(["title": .string("Tape")]),
                    .object(["quantity": .int(2)])
                ])
            ])
        }
        #expect(items(in: context).isEmpty)
    }

    @Test("list_orders shows the office run and to-order apart, labeling a staple's need")
    func listSplitsOfficeRunFromToOrder() async throws {
        let (tools, context) = try makeTools()
        let author = RestockAuthor(role: .leadGuide)
        _ = RestockService.addStaple(.init(name: "Paper Towels"), level: .out, by: author, in: context)
        _ = RestockService.addOneOff(title: "Easel", link: URL(string: "https://example.com/easel"), by: author, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let listing = try await tool(named: "list_orders", in: tools).handler([:])
        let office = try #require(listing.range(of: "office run (1)"))
        let order = try #require(listing.range(of: "to order, to_request (1)"))
        #expect(office.lowerBound < order.lowerBound)
        let lines = listing.components(separatedBy: "\n")
        let towels = try #require(lines.first { $0.contains("Paper Towels") })
        #expect(towels.contains("staple need"))
        let easel = try #require(lines.first { $0.contains("Easel") })
        #expect(!easel.contains("staple need"))
    }

    @Test("Receiving a staple's need puts the staple back to Stocked; an office need can't be asked for")
    func receivingAStapleNeedRestocks() async throws {
        let (tools, context) = try makeTools()
        let author = RestockAuthor(role: .leadGuide)
        let towels = try #require(RestockService.addStaple(
            .init(name: "Paper Towels"), level: .out, by: author, in: context
        )).object
        #expect(CoreDataTestHelpers.save(context))
        let need = try #require(RestockService.openNeeds(for: towels, in: context).first)
        let id = try #require(need.id?.uuidString)
        let update = try tool(named: "update_order_items", in: tools)

        await #expect(throws: MCPToolError.self) {
            _ = try await update.handler([
                "items": .array([.object(["id": .string(id), "stage": .string("asked_for")])])
            ])
        }
        #expect(need.stage == .toRequest)

        _ = try await update.handler([
            "items": .array([.object(["id": .string(id), "stage": .string("received")])])
        ])
        #expect(need.stage == .received)
        #expect(towels.level == .stocked)
    }
}
