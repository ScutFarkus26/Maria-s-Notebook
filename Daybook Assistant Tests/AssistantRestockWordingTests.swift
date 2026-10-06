import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// What the tab reads from what she types, and how it names who changed
// something: her name as it is now, another assistant, the hold menu's header.
@Suite("Assistant Restock: who and what")
@MainActor
struct AssistantRestockWordingTests {

    private let stack: CoreDataStack
    private static let guide = AssistantRestockTestSupport.guide

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    @discardableResult
    private func staple(
        _ name: String,
        place: String = "Bathrooms",
        source: RestockSource = .office,
        level: RestockLevel = .stocked
    ) throws -> CDSupply {
        try AssistantRestockTestSupport.staple(name, place: place, source: source, level: level, in: context)
    }

    private func model(
        now: Date = Date(),
        author: RestockAuthor = AssistantRestockTestSupport.ana,
        save: AssistantRestockModel.Save? = nil
    ) -> AssistantRestockModel {
        AssistantRestockTestSupport.model(in: context, now: now, author: author, save: save)
    }

    // MARK: - What she types

    @Test("A sentence's closing period is not a link: Kleenex. is Kleenex, Toilet paper. is the staple")
    func trailingPeriod() throws {
        let paper = try staple("Toilet Paper")
        let tab = model()
        #expect(AssistantRestockModel.pastedLink("Kleenex.") == nil)
        #expect(AssistantRestockModel.pastedLink("Mr.Sketch") == nil)
        #expect(AssistantRestockModel.pastedLink("amazon.com/dp/x")?.host() == "amazon.com")
        #expect(AssistantRestockModel.pastedLink("amazon.com/dp/x.")?.absoluteString == "https://amazon.com/dp/x")
        #expect(AssistantRestockModel.pastedLink("https://example.shop/glue") != nil)

        #expect(tab.addNeed("Kleenex.", source: .office, quantity: 1) == .added)
        let kleenex = try #require(tab.officeRun.first)
        #expect(kleenex.title == "Kleenex")
        #expect(kleenex.urlString.isEmpty)

        #expect(tab.staple(named: "Toilet paper.") == paper)
        #expect(tab.addNeed("Toilet paper.", source: .office, quantity: 1) == .markedStaple)
        #expect(paper.level == .out)
    }

    // MARK: - Who and when

    @Test("Another assistant who gave no name reads as another assistant, not your guide")
    func unnamedSecondAssistant() throws {
        let now = try AssistantTestSupport.day("2026-10-03").addingTimeInterval(8 * 3_600)
        let bea = RestockAuthor(role: .assistant, recordName: "_bea")
        let towels = try #require(RestockService.addStaple(
            .init(name: "Paper Towels"), level: .out, by: bea, at: now, in: context
        )).object
        let soap = try #require(RestockService.addStaple(
            .init(name: "Hand Soap"), level: .low, by: Self.guide, at: now, in: context
        )).object
        let anaInClass = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana", ownerRecordName: "_guide")
        let tab = model(now: now, author: anaInClass)
        let time = now.formatted(date: .omitted, time: .shortened)

        #expect(tab.markedBy(towels) == "Another assistant · \(time)")
        #expect(tab.markedBy(soap) == "Your guide · \(time)")
    }

    @Test("A change is stamped with her name as it is at the time, not when the tab opened")
    func authorReadAtWriteTime() throws {
        let paper = try staple("Toilet Paper")
        let previousRecord = ClassroomIdentity.currentUserRecordName
        let previousName = ClassroomIdentity.displayName
        defer {
            ClassroomIdentity.currentUserRecordName = previousRecord
            ClassroomIdentity.displayName = previousName
        }
        ClassroomIdentity.currentUserRecordName = nil
        ClassroomIdentity.displayName = nil
        let tab = AssistantRestockModel.live(context: context, container: nil)
        tab.load()

        // She types her name, and iCloud sends her record name, after the tab was made.
        ClassroomIdentity.currentUserRecordName = "_bea"
        ClassroomIdentity.displayName = "Bea"
        tab.tap(paper)
        #expect(paper.levelChangedByName == "Bea")
        #expect(paper.levelChangedByID == "_bea")
        #expect(tab.markedBy(paper)?.hasPrefix("You · ") == true)
    }

    // MARK: - Names from the classroom's list

    @Test("Each fixed sentence names the guide when he set a name, and says your guide when he hasn't")
    func guideSentences() throws {
        let clay = try staple("Air Dry Clay", place: "Art shelf", source: .order)

        let unnamed = model()
        #expect(unnamed.guideName == nil)
        #expect(unnamed.orderingTitle == "Your guide is ordering")
        #expect(unnamed.ordersIt == "Your guide orders it")
        #expect(unnamed.emptyShelfMessage
            == "Your guide adds the things the class always needs. Tap + to ask for something else.")
        #expect(unnamed.sendsTheOrder == "Your guide sends the order")
        #expect(unnamed.askToOrder == "Ask Your Guide to Order")
        #expect(unnamed.seesNoteToo == "Your guide sees this note too.")
        #expect(unnamed.menuHeader(clay).hasSuffix("by your guide · Art shelf · Your guide orders it"))

        let named = model(author: AssistantRestockTestSupport.ana.reading(.init(guideName: "Danny")))
        #expect(named.guideName == "Danny")
        #expect(named.orderingTitle == "Danny is ordering")
        #expect(named.ordersIt == "Danny orders it")
        #expect(named.emptyShelfMessage
            == "Danny adds the things the class always needs. Tap + to ask for something else.")
        #expect(named.sendsTheOrder == "Danny sends the order")
        #expect(named.askToOrder == "Ask Danny to Order")
        #expect(named.seesNoteToo == "Danny sees this note too.")
        // His old change, stamped with no name, reads his name too.
        #expect(named.menuHeader(clay).hasSuffix("by Danny · Art shelf · Danny orders it"))
    }

    @Test("The live tab names the guide from the classroom's list first, then Apple's name, and follows a rename")
    func liveGuideName() throws {
        let now = try AssistantTestSupport.day("2026-10-03").addingTimeInterval(8 * 3_600)
        let soap = try #require(RestockService.addStaple(
            .init(name: "Hand Soap"), level: .low, by: Self.guide, at: now, in: context
        )).object
        // The live tab reads the real clock: a change on another day shows its date.
        let time = AssistantRestockModel.when(now, now: Date())

        try AssistantRestockTestSupport.asIdentity("_ana", named: "Ana") {
            let none = AssistantRestockModel.live(context: context, container: nil)
            #expect(none.guideName == nil)
            #expect(none.orderingTitle == "Your guide is ordering")

            let tab = AssistantRestockModel.live(context: context, container: nil, guideName: { "Daniel DeBerry" })
            tab.load()
            #expect(tab.guideName == "Daniel DeBerry")
            #expect(tab.markedBy(soap) == "Daniel DeBerry · \(time)")

            // He sets his name on his Mac; it arrives, and the tab reloads.
            let row = AssistantRestockTestSupport.person("_guide", "Danny", role: .leadGuide, at: now, in: context)
            tab.load()
            #expect(tab.guideName == "Danny")
            #expect(tab.orderingTitle == "Danny is ordering")
            #expect(tab.markedBy(soap) == "Danny · \(time)")

            row.displayName = "Mr. D"
            row.modifiedAt = now.addingTimeInterval(60)
            #expect(context.safeSave())
            tab.load()
            #expect(tab.markedBy(soap) == "Mr. D · \(time)")
            let need = try #require(tab.officeRun.first)
            #expect(tab.runWho(need).contains("by Mr. D"))
        }
    }

    @Test("Another assistant's current name beats the one her old change was stamped with, rename included")
    func otherAssistantsCurrentName() throws {
        let now = try AssistantTestSupport.day("2026-10-03").addingTimeInterval(8 * 3_600)
        let ana = AssistantRestockTestSupport.ana
        let towels = try #require(RestockService.addStaple(
            .init(name: "Paper Towels"), level: .out, by: ana, at: now, in: context
        )).object
        let bea = RestockAuthor(role: .assistant, recordName: "_bea")
        let tissues = try #require(RestockService.addStaple(
            .init(name: "Tissues"), level: .low, by: bea, at: now, in: context
        )).object
        let time = AssistantRestockModel.when(now, now: Date())

        AssistantRestockTestSupport.asIdentity("_cal", named: "Cal") {
            let tab = AssistantRestockModel.live(context: context, container: nil)
            tab.load()
            #expect(tab.markedBy(towels) == "Ana · \(time)")

            // Ana renames herself "Anna"; Bea, who never typed a name here,
            // sets "Beatrice". Both reach their old changes.
            let anna = AssistantRestockTestSupport.person("_ana", "Anna", at: now, in: context)
            AssistantRestockTestSupport.person("_bea", "Beatrice", at: now, in: context)
            tab.load()
            #expect(tab.markedBy(towels) == "Anna · \(time)")
            #expect(tab.markedBy(tissues) == "Beatrice · \(time)")

            // Clearing her name brings back the one her change was stamped with.
            anna.displayName = ""
            anna.modifiedAt = now.addingTimeInterval(60)
            #expect(context.safeSave())
            tab.load()
            #expect(tab.markedBy(towels) == "Ana · \(time)")
        }
    }

    @Test("A staple's history names each person as they go by now; a count with no reason reads as its number")
    func historyNamesCurrentNames() throws {
        let now = try AssistantTestSupport.day("2026-10-03").addingTimeInterval(8 * 3_600)
        let towels = try #require(RestockService.addStaple(
            .init(name: "Paper Towels"), level: .low, by: AssistantRestockTestSupport.ana, at: now, in: context
        )).object
        RestockService.setLevel(towels, to: .out, by: Self.guide, at: now.addingTimeInterval(60), in: context)
        let counted = CDSupplyTransaction(context: context)
        counted.supplyID = towels.id?.uuidString ?? ""
        counted.date = now.addingTimeInterval(180)
        counted.quantityChange = -2
        #expect(context.safeSave())
        AssistantRestockTestSupport.person("_ana", "Anna", at: now, in: context)

        AssistantRestockTestSupport.asIdentity("_ana", named: "Anna") {
            let tab = AssistantRestockModel.live(context: context, container: nil)
            tab.load()
            let lines = tab.history(for: towels).map {
                AssistantRestockHistorySheet.line(for: $0, names: tab.author.names)
            }
            #expect(lines == ["−2", "Out", "Low · Anna"], "stamped 'Ana', she goes by 'Anna' now")
        }
    }

    @Test("The hold menu says Added for a staple never changed, and that the guide orders an ordered one")
    func menuHeaderWording() throws {
        let soap = try staple("Hand Soap")
        let clay = try staple("Air Dry Clay", place: "Art shelf", source: .order)
        let towels = try staple("Paper Towels", level: .out)
        let tab = model()
        tab.setLevel(towels, to: .stocked)

        #expect(tab.menuHeader(soap).hasPrefix("Added "))
        #expect(tab.menuHeader(soap).contains("by your guide · Bathrooms · From the office"))
        #expect(tab.menuHeader(clay).hasSuffix("Art shelf · Your guide orders it"))
        #expect(tab.menuHeader(towels).hasPrefix("Restocked "))
    }
}
