import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The Orders list: a dropped link becomes an item, one request asks for
/// everything not yet asked for, and each item is followed through confirmed
/// and received. The stage is read off the dates, so these tests pin the
/// transitions by the stage they produce.
@Suite("Orders")
@MainActor
struct OrderServiceTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func link(_ path: String) -> URL {
        URL(string: "https://www.example.com/\(path)")!
    }

    // MARK: - Links

    @Test("A typed link gains https, and anything that isn't a web page is refused")
    func typedLinks() {
        #expect(OrderService.webURL(from: "  example.com/pencils ")?.absoluteString == "https://example.com/pencils")
        #expect(OrderService.webURL(from: "http://example.com")?.absoluteString == "http://example.com")
        #expect(OrderService.webURL(from: "not a link") == nil)
        #expect(OrderService.webURL(from: "") == nil)
        #expect(OrderService.webURL(from: "file:///Users/guide/list.pdf") == nil)
        #expect(!OrderService.isWebURL(URL(fileURLWithPath: "/tmp/order.pdf")))
    }

    @Test("A link already waiting is not added twice, but can be re-ordered once received")
    func duplicateLinks() throws {
        let context = try makeContext()
        let first = OrderService.addLinks([link("pencils"), link("PENCILS/")], in: context)
        #expect(first.count == 1, "the same page dropped twice in one go is one item")

        let again = OrderService.addLinks([link("pencils")], in: context)
        #expect(again.isEmpty)

        OrderService.setReceived(first, true)
        let reorder = OrderService.addLinks([link("pencils")], in: context)
        #expect(reorder.count == 1, "a received item no longer blocks ordering it again")
    }

    @Test("Adding keeps the title, quantity and note, with at least one of anything")
    func addingFields() throws {
        let context = try makeContext()
        let item = try #require(
            OrderService.addLinks([link("rods")], title: "  Number Rods ", quantity: 0, notes: " red ", in: context).first
        )
        #expect(item.title == "Number Rods")
        #expect(item.quantity == 1)
        #expect(item.notes == "red")
        #expect(item.stage == .toRequest)
        #expect(item.host == "example.com")
    }

    // MARK: - Stages

    @Test("An item moves asked for → confirmed → received, and back")
    func stageTransitions() throws {
        let context = try makeContext()
        let items = OrderService.addLinks([link("a"), link("b")], in: context)

        OrderService.markRequested(items, from: "Ms. Rivera")
        #expect(items.allSatisfy { $0.stage == .requested })
        #expect(Set(items.compactMap(\.requestID)).count == 1, "one request, one id")
        #expect(items.allSatisfy { $0.requestedFrom == "Ms. Rivera" })

        OrderService.markConfirmed(items)
        #expect(items.allSatisfy { $0.stage == .confirmed })

        OrderService.setReceived([items[0]], true)
        #expect(items[0].stage == .received)
        #expect(items[1].stage == .confirmed)

        OrderService.setReceived([items[0]], false)
        #expect(items[0].stage == .confirmed, "unchecking falls back to where it stood")

        OrderService.clearConfirmation([items[1]])
        #expect(items[1].stage == .requested)

        OrderService.moveBackToRequest(items)
        #expect(items.allSatisfy { $0.stage == .toRequest && $0.requestID == nil && $0.requestedFrom.isEmpty })
    }

    @Test("Quantity stays between 1 and 999, and an unchanged count leaves the item untouched")
    func quantityClamps() throws {
        let context = try makeContext()
        let item = try #require(OrderService.addLinks([link("a")], quantity: 5_000, in: context).first)
        #expect(item.quantity == 999)

        OrderService.setQuantity(item, to: 0)
        #expect(item.quantity == 1)

        OrderService.setQuantity(item, to: 3, at: Date(timeIntervalSince1970: 1_000))
        #expect(item.quantity == 3)
        OrderService.setQuantity(item, to: 3, at: Date(timeIntervalSince1970: 2_000))
        #expect(item.modifiedAt == Date(timeIntervalSince1970: 1_000), "no change, no new modifiedAt")
    }

    @Test("Confirming twice keeps the first confirmation date")
    func confirmIsIdempotent() throws {
        let context = try makeContext()
        let items = OrderService.addLinks([link("a")], in: context)
        let first = Date(timeIntervalSince1970: 1_000)
        OrderService.markConfirmed(items, at: first)
        OrderService.markConfirmed(items, at: Date(timeIntervalSince1970: 2_000))
        #expect(items[0].confirmedAt == first)
    }

    @Test("Asked-for items group by request, the longest-waiting first")
    func requestGrouping() throws {
        let context = try makeContext()
        let older = OrderService.addLinks([link("a"), link("b")], in: context)
        let newer = OrderService.addLinks([link("c")], in: context)
        let confirmed = OrderService.addLinks([link("d")], in: context)
        OrderService.markRequested(older, from: "Office", at: Date(timeIntervalSince1970: 1_000))
        OrderService.markRequested(newer, from: "Office", at: Date(timeIntervalSince1970: 5_000))
        OrderService.markRequested(confirmed, from: "Office", at: Date(timeIntervalSince1970: 500))
        OrderService.markConfirmed(confirmed)

        let groups = OrderService.openRequests(older + newer + confirmed)
        #expect(groups.map(\.items.count) == [2, 1], "a confirmed request is no longer waiting")
        #expect(groups.first?.requestedAt == Date(timeIntervalSince1970: 1_000))
        #expect(groups.first?.requestedFrom == "Office")
    }

    // MARK: - The Request Email

    @Test("The request lists each item with its link, quantity and note")
    func messageBody() {
        let lines = [
            OrderRequestLine(title: "Colored Pencils", link: "https://example.com/p", quantity: 2, notes: "24 count"),
            OrderRequestLine(title: "Glue Sticks", link: "https://example.com/g", quantity: 1, notes: "")
        ]
        let body = OrderRequestMessage.body(for: lines, recipientName: "Maria", signOff: "Danny")
        #expect(body == """
            Hi Maria,

            Could you please order these for my classroom?

            1. Colored Pencils
                Quantity: 2
                https://example.com/p
                Note: 24 count

            2. Glue Sticks
                Quantity: 1
                https://example.com/g

            Thank you!
            Danny
            """)
        #expect(OrderRequestMessage.subject(for: lines) == "Order request: 2 items")
    }

    @Test("One item, no recipient name and no sign-off still read naturally")
    func messageFallbacks() {
        let line = OrderRequestLine(title: "Stapler", link: "", quantity: 1, notes: "")
        let body = OrderRequestMessage.body(for: [line], recipientName: "  ", signOff: "")
        #expect(body.hasPrefix("Hi,\n\nCould you please order this for my classroom?"))
        #expect(body.hasSuffix("1. Stapler\n    Quantity: 1\n\nThank you!"))
        #expect(OrderRequestMessage.subject(for: [line]) == "Order request: Stapler")
    }

    @Test("Several recipient addresses are split, and the list shows the name when there is one")
    func recipient() {
        let recipient = OrderRequestRecipient(name: "Front Office", email: "a@school.org; b@school.org")
        #expect(recipient.emails == ["a@school.org", "b@school.org"])
        #expect(recipient.isConfigured)
        #expect(recipient.label == "Front Office")
        #expect(!OrderRequestRecipient(name: "Maria", email: " ").isConfigured)
    }
}
