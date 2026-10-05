import Foundation
import CoreData
import Synchronization
import Testing
@testable import Daybook_Assistant

// The Restock commands Siri runs ("We're out of…", "We're low on…", "Add … to
// the office run"), on an in-memory stack through `AssistantSiriRestock`, and
// the names they hear.
@Suite("Assistant Siri Restock", .serialized)
@MainActor
struct AssistantSiriRestockTests {

    private let stack: CoreDataStack
    private static let guide = RestockAuthor(role: .leadGuide, recordName: "_guide")
    private static let ana = RestockAuthor(role: .assistant, recordName: "_ana", name: "Ana")

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }
    private var siri: AssistantSiriRestock { AssistantSiriRestock(stack: stack, author: Self.ana) }

    @discardableResult
    private func staple(
        _ name: String,
        source: RestockSource = .office,
        level: RestockLevel = .stocked
    ) throws -> CDSupply {
        let details = RestockService.StapleDetails(name: name, place: "Sink", source: source)
        let added = try #require(RestockService.addStaple(details, level: level, by: Self.guide, in: context))
        #expect(context.safeSave())
        return added.object
    }

    private func id(_ staple: CDSupply) throws -> UUID { try #require(staple.id) }

    @Test("Apple's cap is ten: attendance's six and Restock's three")
    func nineShortcuts() {
        #expect(AssistantAppShortcuts.appShortcuts.count == 9)
    }

    @Test("We're out of… marks the staple Out, opens its need and saves")
    func markOut() throws {
        let towels = try staple("Paper Towels")
        #expect(try siri.mark(id(towels), as: .out) == .marked("Paper Towels", .out, .office))
        #expect(towels.level == .out)
        #expect(towels.levelChangedByName == "Ana")
        #expect(RestockService.openNeeds(for: towels, in: context).count == 1)
        #expect(!context.hasChanges)

        #expect(try siri.mark(id(towels), as: .out) == .already("Paper Towels", .out))
        #expect(RestockService.history(for: towels, in: context).count == 1)
    }

    @Test("We're low on… marks it Low, never takes an Out staple back up, and names the order list")
    func markLow() throws {
        let clay = try staple("Air Dry Clay", source: .order)
        let paper = try staple("Toilet Paper", level: .out)

        let outcome = try siri.mark(id(clay), as: .low)
        #expect(outcome == .marked("Air Dry Clay", .low, .order))
        #expect(outcome.spoken().contains("It's on your guide's order list."))
        #expect(outcome.spoken(guideName: "Danny").contains("It's on Danny's order list."))
        // Siri reads the guide's name from the classroom's list itself.
        AssistantRestockTestSupport.person("_guide", "Danny", role: .leadGuide, in: context)
        let named = AssistantSiriRestock(stack: stack, author: Self.ana.reading(ClassroomNames.snapshot(in: context)))
        #expect(named.guideName == "Danny")
        #expect(siri.guideName == nil)
        #expect(clay.level == .low)

        #expect(try siri.mark(id(paper), as: .low) == .already("Toilet Paper", .out))
        #expect(paper.level == .out)

        #expect(throws: AssistantRestockSiriError.notFound) { try siri.mark(UUID(), as: .out) }
    }

    @Test("Add to the office run adds a one-off once, and a staple's name marks the staple low")
    func addToOfficeRun() throws {
        let towels = try staple("Paper Towels")

        #expect(try siri.addToOfficeRun(" Glue sticks ") == .added("Glue sticks"))
        let glue = try #require(RestockService.openNeeds(in: context).first { $0.title == "Glue sticks" })
        #expect(glue.source == .office)
        #expect(glue.addedByName == "Ana")
        #expect(!context.hasChanges)
        #expect(try siri.addToOfficeRun("glue sticks") == .alreadyListed("Glue sticks"))

        #expect(try siri.addToOfficeRun("the paper towels") == .marked("Paper Towels", .low, .office))
        #expect(towels.level == .low)
        #expect(try siri.addToOfficeRun("paper towels") == .already("Paper Towels", .low))
        #expect(RestockService.openNeeds(in: context).count == 2)

        #expect(throws: AssistantRestockSiriError.noName) { try siri.addToOfficeRun("  ") }
    }

    @Test("A word in two staples' names marks neither: \"paper\" is a one-off, \"towels\" is Paper Towels")
    func ambiguousNameIsAOneOff() throws {
        let towels = try staple("Paper Towels")
        let paper = try staple("Toilet Paper")

        #expect(try siri.addToOfficeRun("paper") == .added("paper"))
        #expect(towels.level == .stocked)
        #expect(paper.level == .stocked)
        #expect(RestockService.openNeeds(in: context).map(\.title) == ["paper"])

        #expect(try siri.addToOfficeRun("towels") == .marked("Paper Towels", .low, .office))
        #expect(towels.level == .low)
    }

    @Test("A failed save takes back Siri's change alone: the tab's taps waiting to save stay, and it reloads")
    func failedSaveKeepsTheTabsTaps() throws {
        let paper = try staple("Toilet Paper")
        let towels = try staple("Paper Towels")
        let tab = AssistantRestockModel(
            context: context, container: nil, author: { Self.ana }, saveDelay: .seconds(600)
        )
        tab.load()
        tab.tap(paper)
        let reloads = ReloadCount()
        let observer = NotificationCenter.default.addObserver(
            forName: .restockChangedBySiri, object: nil, queue: nil
        ) { _ in reloads.count.withLock { $0 += 1 } }
        defer { NotificationCenter.default.removeObserver(observer) }

        let failing = AssistantSiriRestock(stack: stack, author: Self.ana, save: { _ in false })
        #expect(throws: AssistantRestockSiriError.saveFailed) { try failing.mark(id(towels), as: .out) }
        #expect(throws: AssistantRestockSiriError.saveFailed) { try failing.addToOfficeRun("Glue sticks") }

        #expect(towels.level == .stocked)
        #expect(RestockService.openNeeds(for: towels, in: context).isEmpty)
        #expect(RestockService.history(for: towels, in: context).isEmpty)
        #expect(RestockService.openNeeds(in: context).map(\.title) == ["Toilet Paper"])
        #expect(paper.level == .low, "the tab's tap is still waiting for its save")
        #expect(context.hasChanges)
        #expect(reloads.count.withLock { $0 } == 2)
    }

    /// How many times the Restock tab was told to reload.
    private final class ReloadCount: Sendable {
        let count = Mutex(0)
    }

    @Test("A spoken name finds its staple: any case, a plural, a leading 'the', or one word of it")
    func names() throws {
        let towels = try staple("Paper Towels")
        let paper = try staple("Toilet Paper")
        let brushes = try staple("Paint Brushes")
        let all = [towels, paper, brushes]

        #expect(AssistantSupplyNames.matches(for: "paper towel", in: all) == [towels])
        #expect(AssistantSupplyNames.matches(for: "The Paper Towels", in: all) == [towels])
        #expect(AssistantSupplyNames.matches(for: "towels", in: all) == [towels])
        #expect(AssistantSupplyNames.matches(for: "paint brush", in: all) == [brushes])
        // "paper" is in two names: Siri asks which.
        #expect(Set(AssistantSupplyNames.matches(for: "paper", in: all)) == [towels, paper])
        #expect(AssistantSupplyNames.matches(for: "glue", in: all).isEmpty)
        #expect(AssistantSupplyNames.matches(for: "", in: all).isEmpty)
    }
}
