import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// One-offs, the office run's rules, two devices' needs for one staple, and
/// what the page reads.
@Suite("Restock: needs")
@MainActor
struct RestockNeedTests {

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

    // MARK: - One-offs

    @Test("A link makes a one-off an order, cleaned and with a short title; no link means the office")
    func oneOffSources() throws {
        let context = try makeContext()
        let link = try #require(URL(string: OrderLinkCleanerTests.chargerLink))
        let charger = try #require(RestockService.addOneOff(
            title: OrderLinkCleanerTests.chargerTitle, link: link, quantity: 2, by: ana, in: context
        ))
        #expect(charger.isNew)
        #expect(charger.object.source == .order)
        #expect(charger.object.urlString == "https://www.amazon.com/dp/B0B2MMB4LJ")
        #expect(charger.object.title == "Anker Nano Phone Charger")
        #expect(charger.object.quantity == 2)
        #expect(charger.object.supplyID == nil)
        #expect(charger.object.addedByName == "Ana")

        let glue = try #require(
            RestockService.addOneOff(title: "  Glue sticks ", note: " the big ones ", by: guide, in: context)
        )
        #expect(glue.object.source == .office)
        #expect(glue.object.urlString.isEmpty)
        #expect(glue.object.title == "Glue sticks")
        #expect(glue.object.notes == "the big ones")
        #expect(glue.object.addedByName.isEmpty)

        #expect(RestockService.addOneOff(title: "   ", by: guide, in: context) == nil)
        let ordered = try #require(RestockService.addOneOff(title: "Stapler", source: .order, by: guide, in: context))
        #expect(ordered.object.source == .order, "a source chosen by hand stands")
    }

    @Test("The same one-off already waiting is returned rather than added twice")
    func oneOffDuplicates() throws {
        let context = try makeContext()
        let link = try #require(URL(string: "https://www.amazon.com/gp/product/B0F8BBBGBM?psc=1"))
        let first = try #require(RestockService.addOneOff(title: "", link: link, by: guide, in: context))
        let again = try #require(RestockService.addOneOff(
            title: "", link: URL(string: "https://amazon.com/dp/B0F8BBBGBM/ref=x"), by: ana, in: context
        ))
        #expect(!again.isNew)
        #expect(again.object.objectID == first.object.objectID)

        let glue = try #require(RestockService.addOneOff(title: "Glue Sticks", by: guide, in: context))
        let glueAgain = try #require(RestockService.addOneOff(title: "glue sticks", by: ana, in: context))
        #expect(!glueAgain.isNew)
        #expect(glueAgain.object.objectID == glue.object.objectID)

        // A staple's open need counts: "paper towels" is already on the office run.
        let towels = try staple("Paper Towels", in: context)
        RestockService.setLevel(towels, to: .out, by: guide, in: context)
        let towelNeed = try #require(RestockService.openNeeds(for: towels, in: context).first)
        let viaSiri = try #require(RestockService.addOneOff(title: "paper towels", by: ana, in: context))
        #expect(viaSiri.object.objectID == towelNeed.objectID)
        #expect(allNeeds(in: context).count == 3)
    }

    @Test("A fetched title fills an empty one, shortened, and never overwrites a typed one")
    func fetchedTitles() throws {
        let context = try makeContext()
        let link = try #require(URL(string: "https://www.example.com/hub"))
        let need = try #require(RestockService.addOneOff(title: "", link: link, by: guide, in: context)).object
        #expect(RestockService.applyFetchedTitle(OrderLinkCleanerTests.hubTitle, to: need))
        #expect(need.title == "ABFCRTTW 4FT 7-Port USB Hub 3.0 for Desktop")
        #expect(!RestockService.applyFetchedTitle("Something else", to: need))
        #expect(need.title == "ABFCRTTW 4FT 7-Port USB Hub 3.0 for Desktop")
    }

    @Test("Needs from the office are never asked for")
    func officeNeedsSkipRequests() throws {
        let context = try makeContext()
        let glue = try #require(RestockService.addOneOff(title: "Glue sticks", by: guide, in: context)).object
        let pens = try #require(RestockService.addOneOff(
            title: "Pens", link: URL(string: "https://www.example.com/pens"), by: guide, in: context
        )).object
        RestockService.markRequested([glue, pens], from: "Front Office")
        #expect(glue.stage == .toRequest)
        #expect(glue.requestID == nil)
        #expect(pens.stage == .requested)
    }

    // MARK: - Two devices

    @Test("Reconcile keeps the oldest open need of a staple, the same one on every device")
    func reconcileKeepsOldest() throws {
        let context = try makeContext()
        let towels = try staple("Paper Towels", in: context)
        let supplyID = try #require(towels.id?.uuidString)
        func need(_ id: String, created: Date) -> CDOrderItem {
            let item = CDOrderItem(context: context)
            item.id = UUID(uuidString: id)
            item.title = "Paper Towels"
            item.source = .order
            item.supplyID = supplyID
            item.createdAt = created
            return item
        }
        let newest = need("00000000-0000-4000-8000-000000000001", created: at(30))
        let tieB = need("00000000-0000-4000-8000-00000000000B", created: at(10))
        let tieA = need("00000000-0000-4000-8000-00000000000A", created: at(10))
        // The newest copy is the one the guide asked for.
        RestockService.markRequested([newest], from: "Office", at: at(40))
        let oneOff = try #require(RestockService.addOneOff(title: "Glue", by: guide, in: context)).object
        #expect(CoreDataTestHelpers.save(context))

        #expect(RestockService.reconcile(in: context) == 2)
        #expect(!tieA.isDeleted)
        #expect(tieB.isDeleted)
        #expect(newest.isDeleted)
        #expect(tieA.requestedAt == at(40), "the kept need takes over the request")
        #expect(tieA.requestedFrom == "Office")
        #expect(!oneOff.isDeleted)
        #expect(CoreDataTestHelpers.save(context))
        #expect(RestockService.reconcile(in: context) == 0, "a second run finds nothing")
    }

    @Test("Reconcile opens the need a Low or Out staple lost once its level has settled, with no history")
    func reconcileOpensMissingNeed() throws {
        let context = try makeContext()
        // Out, and another device checked its need off as it was marked.
        let towels = try staple("Paper Towels", in: context)
        RestockService.setLevel(towels, to: .out, by: ana, at: at(0), in: context)
        OrderService.setReceived(RestockService.openNeeds(for: towels, in: context), true, at: at(1))
        // Low, its need not here yet.
        let soap = try staple("Hand Soap", in: context)
        RestockService.setLevel(soap, to: .low, by: guide, at: at(200), in: context)
        for need in RestockService.openNeeds(for: soap, in: context) {
            context.delete(need)
        }
        // Stocked, with a need still open: left alone.
        let tissues = try staple("Tissues", in: context)
        RestockService.openNeed(for: tissues, by: guide, at: at(5), store: nil, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let history = try context.count(for: CDFetchRequest(CDSupplyTransaction.self))

        #expect(RestockService.reconcile(in: context, now: at(400)) == 1)
        let opened = try #require(RestockService.openNeeds(for: towels, in: context).first)
        #expect(opened.addedByID == "_ana")
        #expect(opened.addedByName == "Ana")
        #expect(opened.createdAt == at(400))
        #expect(opened.source == .office)
        #expect(RestockService.openNeeds(for: soap, in: context).isEmpty, "marked 200 s ago: not settled")
        #expect(tissues.level == .stocked)
        #expect(RestockService.openNeeds(for: tissues, in: context).count == 1)
        #expect(try context.count(for: CDFetchRequest(CDSupplyTransaction.self)) == history)
        #expect(CoreDataTestHelpers.save(context))
        #expect(RestockService.reconcile(in: context, now: at(400)) == 0, "a second run finds nothing")

        #expect(RestockService.reconcile(in: context, now: at(600)) == 1)
        let soapNeed = try #require(RestockService.openNeeds(for: soap, in: context).first)
        #expect(soapNeed.addedByID == "_guide")
        #expect(soapNeed.addedByName.isEmpty)
    }

    // A level set by a build from before `levelChangedAt` has no date; the
    // fetch used to compare it with the cutoff and skip it for good.
    @Test("Reconcile opens the need of a Low staple whose level has no date")
    func reconcileOpensNeedForUndatedLevel() throws {
        let context = try makeContext()
        let glue = try staple("Glue Sticks", in: context)
        RestockService.setLevel(glue, to: .low, by: guide, at: at(0), in: context)
        for need in RestockService.openNeeds(for: glue, in: context) {
            context.delete(need)
        }
        glue.levelChangedAt = nil
        #expect(CoreDataTestHelpers.save(context))

        #expect(RestockService.reconcile(in: context, now: at(10)) == 1)
        #expect(RestockService.openNeeds(for: glue, in: context).count == 1)
    }

    // MARK: - Reading

    @Test("The shelf groups by place, places A to Z and No place yet last")
    func shelfGroups() throws {
        let context = try makeContext()
        _ = try staple("Toilet Paper", place: "Bathrooms", in: context)
        _ = try staple("Paper Towels", place: "bathrooms", in: context)
        _ = try staple("Clay", place: "Art Shelf", in: context)
        _ = try staple("Tape", in: context)
        let groups = RestockService.shelf(RestockService.staples(in: context))
        #expect(groups.map(\.title) == ["Art Shelf", "Bathrooms", "No place yet"])
        #expect(groups[1].staples.map(\.name) == ["Paper Towels", "Toilet Paper"])
    }

    @Test("Open needs are counted by where they come from")
    func needCounts() throws {
        let context = try makeContext()
        let towels = try staple("Paper Towels", in: context)
        RestockService.setLevel(towels, to: .low, by: guide, in: context)
        _ = RestockService.addOneOff(title: "Glue", by: guide, in: context)
        let hub = URL(string: "https://www.example.com/hub")
        _ = RestockService.addOneOff(title: "Hub", link: hub, by: guide, in: context)
        let done = try #require(RestockService.addOneOff(title: "Pens", by: guide, in: context)).object
        RestockService.checkOff(done, by: guide, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let counts = RestockService.openNeedCounts(in: context)
        #expect(counts.officeRun == 2)
        #expect(counts.toOrder == 1)
    }

    @Test("History names its staple by id only, so sharing it never takes the staple along")
    func historyIsNotLinked() throws {
        let context = try makeContext()
        let towels = try staple("Paper Towels", in: context)
        RestockService.setLevel(towels, to: .low, by: guide, in: context)
        RestockService.setLevel(towels, to: .out, by: guide, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let history = RestockService.history(for: towels, in: context)
        #expect(history.count == 2)
        #expect(history.allSatisfy { $0.supply == nil })

        RestockService.deleteStaple(towels, in: context)
        #expect(CoreDataTestHelpers.save(context))
        let left = try context.count(for: CDFetchRequest(CDSupplyTransaction.self))
        #expect(left == 0)
    }

    @Test("Taking back received puts a restocked staple back to Low with the same need")
    func reopenRestockedStaple() throws {
        let context = try makeContext()
        let towels = try staple("Paper Towels", in: context)
        RestockService.setLevel(towels, to: .out, by: guide, in: context)
        let need = try #require(RestockService.openNeeds(for: towels, in: context).first)
        RestockService.checkOff(need, by: guide, in: context)
        #expect(towels.level == .stocked)

        RestockService.reopen([need], by: guide, in: context)
        #expect(towels.level == .low)
        #expect(RestockService.openNeeds(for: towels, in: context).map(\.objectID) == [need.objectID])

        RestockService.checkOff(need, by: guide, in: context)
        RestockService.moveBackToRequest([need], by: guide, in: context)
        #expect(towels.level == .low)
        #expect(need.stage == .toRequest)
        #expect(RestockService.openNeeds(for: towels, in: context).count == 1)
    }

    @Test("Who changed it reads You, a name, or your guide")
    func whoReads() {
        let guideViewer = guide
        let anaViewer = ana
        #expect(guideViewer.reads(changedByID: "_guide", name: "") == "You")
        #expect(guideViewer.reads(changedByID: "_ana", name: "Ana") == "Ana")
        #expect(guideViewer.reads(changedByID: "_rivka", name: "") == "an assistant")
        #expect(guideViewer.reads(changedByID: nil, name: nil) == "You")
        #expect(anaViewer.reads(changedByID: "_ana", name: "Ana") == "You")
        #expect(anaViewer.reads(changedByID: "_guide", name: "") == "your guide")
        #expect(anaViewer.reads(changedByID: "_rivka", name: "Rivka") == "Rivka")
        // Her own change from before her phone knew its record name.
        #expect(anaViewer.reads(changedByID: nil, name: "Ana") == "You")
        #expect(RestockService.historyReason(for: .low, by: ana) == "Low · Ana")
        #expect(RestockService.historyReason(for: .out, by: guide) == "Out")
        #expect(RestockService.historyReason(for: .stocked, by: guide) == "Restocked")
    }

    @Test("On an assistant's phone, another assistant who gave no name isn't read as her guide")
    func whoReadsAnotherAssistant() {
        let anaInClass = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana", ownerRecordName: "_guide")
        #expect(anaInClass.reads(changedByID: "_bea", name: "") == "another assistant")
        #expect(anaInClass.reads(changedByID: "_guide", name: "") == "your guide")
        #expect(anaInClass.reads(changedByID: nil, name: nil) == "your guide")
        #expect(anaInClass.reads(changedByID: "_ana", name: "") == "You")
        #expect(anaInClass.reads(changedByID: "_bea", name: "Bea") == "Bea")
        // Before her phone knows who the guide is, an unnamed change is still the guide's.
        #expect(ana.reads(changedByID: "_bea", name: "") == "your guide")
    }
}

// MARK: - Two needs merged (bug hunt 2026-10-09 #20)

extension RestockNeedTests {

    @Test("Merging two needs keeps what the office was asked for: how many, the note, the name and the link")
    func reconcileKeepsWhatWasAskedFor() throws {
        let context = try makeContext()
        let towels = try staple("Paper Towels", in: context)
        let supplyID = try #require(towels.id?.uuidString)
        func need(created: Date) -> CDOrderItem {
            let item = CDOrderItem(context: context)
            item.title = "Paper Towels"
            item.source = .order
            item.supplyID = supplyID
            item.createdAt = created
            return item
        }
        let older = need(created: at(10))
        let asked = need(created: at(20))
        asked.quantity = 6
        asked.notes = "The big rolls"
        asked.title = "Bounty Paper Towels"
        asked.urlString = "https://www.example.com/towels"
        RestockService.markRequested([asked], from: "Office", at: at(40))
        #expect(CoreDataTestHelpers.save(context))

        #expect(RestockService.reconcile(in: context) == 1)
        #expect(asked.isDeleted)
        #expect(older.requestedAt == at(40))
        #expect(older.quantity == 6, "Asked For shows the 6 the office was asked for, not 1")
        #expect(older.notes == "The big rolls")
        #expect(older.title == "Bounty Paper Towels")
        #expect(older.urlString == "https://www.example.com/towels")
        #expect(older.stage == .requested)
    }

    @Test("Merging keeps the kept need's name and link when the asked-for copy has none")
    func reconcileKeepsOwnNameWhenAskedHasNone() throws {
        let context = try makeContext()
        let glue = try staple("Glue Sticks", in: context)
        let supplyID = try #require(glue.id?.uuidString)
        let older = CDOrderItem(context: context)
        older.title = "Glue Sticks"
        older.urlString = "https://www.example.com/glue"
        older.supplyID = supplyID
        older.source = .order
        older.createdAt = at(10)
        let asked = CDOrderItem(context: context)
        asked.title = " "
        asked.supplyID = supplyID
        asked.source = .order
        asked.quantity = 3
        asked.createdAt = at(20)
        RestockService.markRequested([asked], from: "Office", at: at(30))
        #expect(CoreDataTestHelpers.save(context))

        #expect(RestockService.reconcile(in: context) == 1)
        #expect(older.title == "Glue Sticks")
        #expect(older.urlString == "https://www.example.com/glue")
        #expect(older.quantity == 3)
    }
}
