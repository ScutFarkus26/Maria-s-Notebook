import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The Restock tab on an in-memory stack: the tile's tap cycle, the office
// run's check-off and its Undo, "We need…", the guide's orders as the phone
// reads them, and the sample class's shelf.
@Suite("Assistant Restock")
@MainActor
struct AssistantRestockTests {

    private let stack: CoreDataStack
    private static let guide = RestockAuthor(role: .leadGuide, recordName: "_guide")
    private static let ana = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana")

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    /// Ana's tab. A long save delay, so each test saves when it says (`flush`).
    private func model(now: Date = Date()) -> AssistantRestockModel {
        let model = AssistantRestockModel(
            context: context, container: nil, author: Self.ana, saveDelay: .seconds(600), now: { now }
        )
        model.load()
        return model
    }

    @discardableResult
    private func staple(
        _ name: String,
        place: String = "Bathrooms",
        source: RestockSource = .office,
        level: RestockLevel = .stocked
    ) throws -> CDSupply {
        let details = RestockService.StapleDetails(name: name, place: place, source: source)
        let added = try #require(RestockService.addStaple(details, level: level, by: Self.guide, in: context))
        #expect(context.safeSave())
        return added.object
    }

    // MARK: - The shelf

    @Test("A tap goes Stocked → Low → Out with one need, and a tap on Out changes nothing")
    func tapCycle() throws {
        let paper = try staple("Toilet Paper")
        let tab = model()
        #expect(tab.officeRunCount == 0)

        #expect(tab.tap(paper))
        #expect(paper.level == .low)
        #expect(tab.officeRunCount == 1)
        #expect(tab.tap(paper))
        #expect(paper.level == .out)
        // Low → Out keeps the same need.
        #expect(tab.officeRunCount == 1)
        #expect(tab.officeRun.map(\.title) == ["Toilet Paper"])

        #expect(!tab.tap(paper))
        #expect(paper.level == .out)
        // Both at the same moment here, so in no set order.
        #expect(Set(tab.history(for: paper).map(\.reason)) == ["Out · Ana", "Low · Ana"])
        #expect(tab.history(for: paper).count == 2)
        #expect(paper.levelChangedByName == "Ana")

        // The burst saves once, when asked.
        #expect(context.hasChanges)
        tab.flush()
        #expect(!context.hasChanges)
        #expect(tab.errorMessage == nil)
    }

    @Test("The hold menu sets any level; We have plenty takes a need never asked for off the run")
    func holdMenuLevels() throws {
        let towels = try staple("Paper Towels", level: .out)
        let tab = model()
        #expect(tab.officeRunCount == 1)

        tab.setLevel(towels, to: .stocked)
        #expect(towels.level == .stocked)
        #expect(tab.officeRunCount == 0)
        #expect(RestockService.openNeeds(in: context).isEmpty)

        tab.setNote("Top shelf, left", for: towels)
        #expect(towels.notes == "Top shelf, left")
        #expect(tab.menuHeader(towels).hasSuffix("\nTop shelf, left"))
    }

    // MARK: - The office run

    @Test("Checking a staple off restocks it for everyone, and a second tap takes it back")
    func checkOffAndUndo() throws {
        let paper = try staple("Toilet Paper", level: .out)
        let tab = model()
        let need = try #require(tab.officeRun.first)

        tab.toggleCheckOff(need)
        #expect(paper.level == .stocked)
        #expect(need.receivedAt != nil)
        #expect(tab.officeRunCount == 0)
        // Still on the list, ticked, for Undo.
        #expect(tab.officeRun.map(\.objectID) == [need.objectID])
        #expect(tab.isCheckedOff(need))
        tab.flush()

        tab.toggleCheckOff(need)
        #expect(paper.level == .out)
        #expect(need.receivedAt == nil)
        #expect(!tab.isCheckedOff(need))
        #expect(tab.officeRunCount == 1)
        #expect(tab.history(for: paper).map(\.reason) == ["Out"])
    }

    @Test("The office run is what comes from the office; the guide's orders are listed apart")
    func runAndOrders() throws {
        try staple("Air Dry Clay", place: "Art shelf", source: .order, level: .low)
        try staple("Toilet Paper", level: .out)
        let glue = try #require(RestockService.addOneOff(
            title: "Glue sticks", quantity: 12, source: .office, by: Self.guide, in: context
        ))
        #expect(glue.isNew)
        #expect(context.safeSave())
        let tab = model()

        #expect(tab.officeRun.map(\.title) == ["Toilet Paper", "Glue sticks"])
        #expect(tab.ordering.map(\.title) == ["Air Dry Clay"])
        #expect(tab.orderStatus(try #require(tab.ordering.first)) == "Low · not asked yet")
        #expect(tab.runDetail(glue.object) == "Added by your guide")
    }

    @Test("An order asked for reads as asked, how long ago, then confirmed")
    func orderStatus() throws {
        let asked = try AssistantTestSupport.day("2026-09-30").addingTimeInterval(10 * 3_600)
        let today = try AssistantTestSupport.day("2026-10-03").addingTimeInterval(9 * 3_600)
        let order = try #require(RestockService.addOneOff(
            title: "Watercolor Paper", source: .order, by: Self.guide, in: context
        )).object
        #expect(AssistantRestockModel.orderStatus(order, stapleLevel: nil, now: today) == "Not asked yet")

        RestockService.markRequested([order], from: "Front office", at: asked)
        let date = asked.formatted(.dateTime.month(.abbreviated).day())
        #expect(AssistantRestockModel.orderStatus(order, stapleLevel: nil, now: today)
            == "Asked \(date) · waiting 3 days")
        #expect(AssistantRestockModel.orderStatus(order, stapleLevel: nil, now: asked) == "Asked today")

        RestockService.markConfirmed([order], at: today)
        #expect(AssistantRestockModel.orderStatus(order, stapleLevel: nil, now: today).hasPrefix("Confirmed "))
    }

    // MARK: - We need…

    @Test("We need… asks once, and naming a staple marks it Out instead")
    func weNeed() throws {
        let towels = try staple("Paper Towels", place: "Sink")
        let tab = model()

        #expect(tab.addNeed("Glue sticks", source: .office, quantity: 12) == .added)
        let glue = try #require(tab.officeRun.first { $0.title == "Glue sticks" })
        #expect(glue.quantity == 12)
        #expect(glue.addedByName == "Ana")
        #expect(glue.source == .office)
        #expect(!context.hasChanges)

        #expect(tab.addNeed("glue sticks", source: .office, quantity: 1) == .alreadyListed)
        #expect(tab.officeRun.count { $0.title.foldedKey() == "glue sticks" } == 1)

        #expect(tab.addNeed("paper towels", source: .order, quantity: 3) == .markedStaple)
        #expect(towels.level == .out)
        #expect(tab.officeRunCount == 2)

        #expect(tab.addNeed("Kraft paper roll", source: .order, quantity: 2) == .added)
        #expect(tab.ordering.map(\.title) == ["Kraft paper roll"])
        #expect(tab.addNeed("   ", source: .office, quantity: 1) == .nothing)
    }

    @Test("A pasted link becomes the need's link, cleaned; a single word is a name, not a link")
    func weNeedLink() throws {
        let tab = model()
        #expect(tab.addNeed("Glue", source: .office, quantity: 1) == .added)
        let glue = try #require(tab.officeRun.first)
        #expect(glue.title == "Glue")
        #expect(glue.urlString.isEmpty)

        let link = "amazon.com/Crayola-Watercolor/dp/B000HHKAE2/ref=sr_1_3?keywords=paper&utm_source=x"
        #expect(tab.addNeed(link, source: .order, quantity: 2) == .added)
        let order = try #require(tab.ordering.first)
        #expect(order.urlString == "https://www.amazon.com/dp/B000HHKAE2")
        #expect(order.quantity == 2)
        #expect(AssistantRestockModel.pastedLink("Paper towels") == nil)
    }

    // MARK: - Who and when, and two devices

    @Test("A tile says who set its level: You for her own, your guide for the guide's")
    func markedBy() throws {
        let now = try AssistantTestSupport.day("2026-10-03").addingTimeInterval(8 * 3_600)
        let earlier = try AssistantTestSupport.day("2026-10-01").addingTimeInterval(9 * 3_600)
        let details = RestockService.StapleDetails(name: "Paper Towels", place: "Sink")
        let towels = try #require(
            RestockService.addStaple(details, level: .out, by: Self.guide, at: earlier, in: context)
        ).object
        let tissues = try staple("Tissues")
        let tab = model(now: now)

        #expect(tab.markedBy(towels) == "Your guide · \(earlier.formatted(.dateTime.month(.abbreviated).day()))")
        #expect(tab.markedBy(tissues) == nil)
        tab.tap(tissues)
        #expect(tab.markedBy(tissues) == "You · \(now.formatted(date: .omitted, time: .shortened))")
        #expect(tab.menuHeader(towels).hasPrefix("Out since"))
        #expect(tab.menuHeader(towels).contains("marked by your guide · Sink · From the office"))
    }

    @Test("Loading keeps one open need per staple when two devices each opened one")
    func reconcileOnLoad() throws {
        let paper = try staple("Toilet Paper", level: .out)
        // Another device's copy, newer, arriving by import.
        RestockService.openNeed(for: paper, by: Self.guide, at: Date().addingTimeInterval(60), store: nil, in: context)
        #expect(context.safeSave())
        #expect(RestockService.openNeeds(for: paper, in: context).count == 2)

        let tab = model()
        #expect(RestockService.openNeeds(for: paper, in: context).count == 1)
        #expect(tab.officeRunCount == 1)
        #expect(!context.hasChanges)
    }

    // MARK: - Sample class

    @Test("The sample class has a shelf: two places, five staples, toilet paper out and towels low")
    func sampleShelf() throws {
        let sample = try AssistantSampleClass.makeStack()
        let tab = AssistantRestockModel(
            context: sample.viewContext, container: nil, author: RestockAuthor(role: .assistant)
        )
        tab.load()

        #expect(tab.shelf.map(\.title) == ["Bathrooms", "Sink"])
        #expect(tab.staples.count == 5)
        let levels = Dictionary(uniqueKeysWithValues: tab.staples.map { ($0.name, $0.level) })
        #expect(levels["Toilet Paper"] == .out)
        #expect(levels["Paper Towels"] == .low)
        #expect(levels.values.count { $0 == .stocked } == 3)
        #expect(tab.officeRun.map(\.title) == ["Paper Towels", "Glue sticks", "Toilet Paper"])
        #expect(tab.ordering.count == 2)
        #expect(tab.ordering.contains { $0.stage == .requested })
        #expect(!sample.viewContext.hasChanges)
    }
}
