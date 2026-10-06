import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A staple's level opens and closes its one need, checking that need off
/// restocks it, and editing or deleting a staple carries to its need.
@Suite("Restock: staples and levels")
@MainActor
struct RestockStapleTests {

    private let guide = RestockTestSupport.guide
    private let ana = RestockTestSupport.ana

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeContext()
    }

    private func at(_ seconds: TimeInterval) -> Date {
        RestockTestSupport.at(seconds)
    }

    private func staple(
        _ name: String,
        place: String = "",
        source: RestockSource = .office,
        link: URL? = nil,
        in context: NSManagedObjectContext
    ) throws -> CDSupply {
        try RestockTestSupport.staple(name, place: place, source: source, link: link, in: context)
    }

    private func allNeeds(in context: NSManagedObjectContext) -> [CDOrderItem] {
        RestockTestSupport.allNeeds(in: context)
    }

    // MARK: - Levels and the one open need

    @Test("Low opens one need, Out keeps it, and Stocked deletes it when it was never asked for")
    func levelsOpenAndCloseTheNeed() throws {
        let context = try makeContext()
        let towels = try staple("Paper Towels", place: "Bathrooms", in: context)
        #expect(towels.level == .stocked)
        #expect(RestockService.openNeeds(for: towels, in: context).isEmpty)
        #expect(RestockService.history(for: towels, in: context).isEmpty, "adding at Stocked writes no history")

        #expect(RestockService.setLevel(towels, to: .low, by: ana, at: at(10), in: context))
        let need = try #require(RestockService.openNeeds(for: towels, in: context).first)
        #expect(RestockService.openNeeds(for: towels, in: context).count == 1)
        #expect(need.title == "Paper Towels")
        #expect(need.source == .office)
        #expect(need.supplyID == towels.id?.uuidString)
        #expect(need.addedByID == "_ana")
        #expect(need.addedByName == "Ana")
        #expect(towels.levelChangedAt == at(10))
        #expect(towels.levelChangedByName == "Ana")

        #expect(RestockService.setLevel(towels, to: .out, by: guide, at: at(20), in: context))
        #expect(RestockService.openNeeds(for: towels, in: context).map(\.objectID) == [need.objectID])
        #expect(towels.levelChangedByID == "_guide")
        #expect(towels.levelChangedByName.isEmpty, "the guide's changes carry no name")

        #expect(CoreDataTestHelpers.save(context))
        #expect(RestockService.setLevel(towels, to: .stocked, by: guide, at: at(30), in: context))
        #expect(need.isDeleted)
        #expect(allNeeds(in: context).isEmpty)
        #expect(RestockService.history(for: towels, in: context).map(\.reason) == ["Restocked", "Out", "Low · Ana"])
        #expect(RestockService.history(for: towels, in: context).allSatisfy { $0.quantityChange == 0 })
    }

    @Test("Each level line carries who set it, so a rename reaches it; a stand-in or a count carries no one")
    func historyCarriesWhoSetTheLevel() throws {
        let context = try makeContext()
        let towels = try staple("Paper Towels", in: context)
        RestockService.setLevel(towels, to: .low, by: ana, at: at(10), in: context)
        RestockService.setLevel(towels, to: .out, by: guide, at: at(20), in: context)
        let standIn = RestockAuthor(role: .leadGuide, recordName: "__defaultOwner__")
        RestockService.setLevel(towels, to: .stocked, by: standIn, at: at(30), in: context)
        RestockService.setCount(towels, to: 4, reason: "Counted", at: at(40), in: context)
        #expect(CoreDataTestHelpers.save(context))

        let lines = RestockService.history(for: towels, in: context)
        #expect(lines.map(\.reason) == ["Counted", "Restocked", "Out", "Low · Ana"])
        #expect(lines.map(\.changedByID) == ["", "", "_guide", "_ana"])

        // Ana goes by "Annie" now, and the guide set "Danny" for himself.
        let names = ClassroomNames.Snapshot(
            names: ["_ana": "Annie", "_guide": "Danny"], roles: ["_ana": .assistant, "_guide": .leadGuide]
        )
        let shown = lines.map { StapleHistorySheet.line(for: $0, names: names) }
        #expect(shown == ["Counted", "Restocked", "Out · Danny", "Low · Annie"])
    }

    @Test("Stocked marks a need already asked for as received instead of deleting it")
    func restockingAnAskedForNeed() throws {
        let context = try makeContext()
        let clay = try staple(
            "Air Dry Clay", source: .order, link: URL(string: "https://www.example.com/clay?utm_source=x"), in: context
        )
        #expect(clay.urlString == "https://www.example.com/clay")
        RestockService.setLevel(clay, to: .low, by: guide, in: context)
        let need = try #require(RestockService.openNeeds(for: clay, in: context).first)
        #expect(need.source == .order)
        #expect(need.urlString == "https://www.example.com/clay")
        RestockService.markRequested([need], from: "Front Office", at: at(5))
        #expect(need.stage == .requested)

        RestockService.setLevel(clay, to: .stocked, by: guide, at: at(9), in: context)
        #expect(!need.isDeleted)
        #expect(need.stage == .received)
        #expect(need.receivedAt == at(9))
    }

    @Test("The level a staple already has changes nothing, unless its need has gone missing")
    func sameLevelHeals() throws {
        let context = try makeContext()
        let tissues = try staple("Tissues", in: context)
        #expect(!RestockService.setLevel(tissues, to: .stocked, by: guide, in: context))

        RestockService.setLevel(tissues, to: .out, by: guide, in: context)
        #expect(!RestockService.setLevel(tissues, to: .out, by: guide, in: context))
        #expect(RestockService.history(for: tissues, in: context).count == 1)

        // Another device closed the need as this one marked Out.
        context.delete(try #require(RestockService.openNeeds(for: tissues, in: context).first))
        #expect(RestockService.setLevel(tissues, to: .out, by: guide, in: context))
        #expect(RestockService.openNeeds(for: tissues, in: context).count == 1)
        #expect(RestockService.history(for: tissues, in: context).count == 1, "healing writes no history")
    }

    @Test("A tap goes Stocked → Low → Out and stops at Out")
    func tapCycle() {
        #expect(RestockLevel.stocked.afterTap == .low)
        #expect(RestockLevel.low.afterTap == .out)
        #expect(RestockLevel.out.afterTap == nil)
    }

    // MARK: - Checking off

    @Test("Checking a staple's need off restocks it, and undo puts both back")
    func checkOffRestocksAndUndoes() throws {
        let context = try makeContext()
        let paper = try staple("Toilet Paper", place: "Bathrooms", in: context)
        RestockService.setLevel(paper, to: .out, by: ana, at: at(10), in: context)
        let need = try #require(RestockService.openNeeds(for: paper, in: context).first)

        let checkOff = try #require(RestockService.checkOff(need, by: guide, at: at(20), in: context))
        #expect(need.stage == .received)
        #expect(paper.level == .stocked)
        #expect(paper.levelChangedByID == "_guide")
        #expect(RestockService.history(for: paper, in: context).first?.reason == "Restocked")
        #expect(RestockService.checkOff(need, by: guide, in: context) == nil, "already checked off")

        RestockService.undoCheckOff(checkOff, at: at(25), in: context)
        #expect(need.receivedAt == nil)
        #expect(paper.level == .out)
        #expect(paper.levelChangedAt == at(10))
        #expect(paper.levelChangedByName == "Ana")
        #expect(RestockService.history(for: paper, in: context).map(\.reason) == ["Out · Ana"])
    }

    @Test("Undo of a check-off is refused once the staple or the need has changed since")
    func undoRefusedAfterAChange() throws {
        let context = try makeContext()
        let paper = try staple("Toilet Paper", place: "Bathrooms", in: context)
        RestockService.setLevel(paper, to: .out, by: guide, at: at(10), in: context)
        let need = try #require(RestockService.openNeeds(for: paper, in: context).first)
        let checkOff = try #require(RestockService.checkOff(need, by: ana, at: at(20), in: context))
        #expect(RestockService.canUndo(checkOff))

        // The guide marks it Low again, and checks that need off too.
        RestockService.setLevel(paper, to: .low, by: guide, at: at(30), in: context)
        let second = try #require(RestockService.openNeeds(for: paper, in: context).first)
        RestockService.checkOff(second, by: guide, at: at(40), in: context)
        #expect(!RestockService.canUndo(checkOff))
        #expect(!RestockService.undoCheckOff(checkOff, at: at(50), in: context))
        #expect(paper.level == .stocked)
        #expect(paper.levelChangedAt == at(40))
        #expect(need.receivedAt == at(20))
        #expect(RestockService.history(for: paper, in: context).count == 4, "her Restocked line stays")

        // A one-off someone else put back on the list first: nothing to take back.
        let glue = try #require(RestockService.addOneOff(title: "Glue sticks", by: guide, in: context)).object
        let glueOff = try #require(RestockService.checkOff(glue, by: ana, at: at(60), in: context))
        RestockService.reopen([glue], by: guide, at: at(70), in: context)
        #expect(!RestockService.undoCheckOff(glueOff, at: at(80), in: context))
        #expect(glue.receivedAt == nil)
    }

    @Test("Checking off a one-off only marks it received")
    func checkOffOneOff() throws {
        let context = try makeContext()
        let glue = try #require(RestockService.addOneOff(title: "Glue sticks", by: guide, in: context)).object
        let checkOff = try #require(RestockService.checkOff(glue, by: guide, at: at(3), in: context))
        #expect(glue.receivedAt == at(3))
        #expect(checkOff.staple == nil)
        #expect(checkOff.history == nil)
    }

    @Test("Removing a staple's open need puts the staple back to Stocked")
    func removingANeedRestocks() throws {
        let context = try makeContext()
        let soap = try staple("Hand Soap", in: context)
        RestockService.setLevel(soap, to: .low, by: guide, in: context)
        let need = try #require(RestockService.openNeeds(for: soap, in: context).first)
        RestockService.removeNeeds([need], by: guide, in: context)
        #expect(soap.level == .stocked)
        #expect(allNeeds(in: context).isEmpty)
    }

    // MARK: - Editing and deleting staples

    @Test("Editing a staple carries its name, link and source to a need not yet asked for")
    func editFollowsNeed() throws {
        let context = try makeContext()
        let clay = try staple("Clay", in: context)
        RestockService.setLevel(clay, to: .low, by: guide, in: context)
        var details = RestockService.StapleDetails(clay)
        details.name = "Air Dry Clay"
        details.source = .order
        details.link = URL(string: "https://www.example.com/clay?fbclid=abc&size=2")
        details.place = " Art Shelf "
        #expect(RestockService.updateStaple(clay, to: details, in: context))
        #expect(clay.location == "Art Shelf")
        let need = try #require(RestockService.openNeeds(for: clay, in: context).first)
        #expect(need.title == "Air Dry Clay")
        #expect(need.source == .order)
        #expect(need.urlString == "https://www.example.com/clay?size=2")
        #expect(!RestockService.updateStaple(clay, to: RestockService.StapleDetails(clay), in: context))

        RestockService.markRequested([need], from: "Office")
        details.name = "Clay, white"
        RestockService.updateStaple(clay, to: details, in: context)
        #expect(need.title == "Air Dry Clay", "what the office was sent stays as sent")
    }

    @Test("Deleting a staple deletes its need not yet asked for and keeps an order in flight as a one-off")
    func deleteStaple() throws {
        let context = try makeContext()
        let towels = try staple("Paper Towels", in: context)
        RestockService.setLevel(towels, to: .out, by: guide, in: context)
        let clay = try staple("Clay", source: .order, in: context)
        RestockService.setLevel(clay, to: .out, by: guide, in: context)
        let clayNeed = try #require(RestockService.openNeeds(for: clay, in: context).first)
        RestockService.markRequested([clayNeed], from: "Office")
        #expect(CoreDataTestHelpers.save(context))

        RestockService.deleteStaple(towels, in: context)
        RestockService.deleteStaple(clay, in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(allNeeds(in: context).map(\.title) == ["Clay"])
        #expect(clayNeed.supplyID == nil)
        #expect(context.safeFetch(CDFetchRequest(CDSupplyTransaction.self)).isEmpty, "history goes with the staple")
    }

    @Test("Adding a staple already on the shelf returns it; adding one at Out opens its need")
    func addStapleCases() throws {
        let context = try makeContext()
        let first = try staple("Paper Towels", in: context)
        let again = try #require(RestockService.addStaple(.init(name: " paper towels "), by: ana, in: context))
        #expect(!again.isNew)
        #expect(again.object.objectID == first.objectID)
        #expect(RestockService.addStaple(.init(name: "  "), by: guide, in: context) == nil)

        let soap = try #require(RestockService.addStaple(
            .init(name: "Hand Soap", place: "Sink"), level: .out, by: ana, at: at(4), in: context
        )).object
        #expect(soap.level == .out)
        #expect(soap.levelChangedAt == at(4))
        #expect(RestockService.openNeeds(for: soap, in: context).count == 1)
        #expect(RestockService.history(for: soap, in: context).map(\.reason) == ["Out · Ana"])
        #expect(first.levelChangedAt != nil, "a staple added Stocked is stamped too")
        #expect(CoreDataTestHelpers.save(context))
    }
}
