import Foundation
import CoreData
import Observation
import os
import Testing
@testable import Daybook_Assistant

// Assistant battery and heat check 2026-10-10, finding 4: every reload (and
// every finished import reloaded) bumped `revision`, which redrew every tile.
// A reload now redraws only when something the tab shows has changed; an
// import changes the same managed objects in place, so a change made
// elsewhere is stood in for by changing them here and saving.
@Suite("Assistant Restock reloads")
@MainActor
struct AssistantRestockReloadTests {

    private let stack: CoreDataStack
    private static let guide = AssistantRestockTestSupport.guide
    private static let ana = AssistantRestockTestSupport.ana

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    /// The clock and the reader, which a test moves.
    private final class Settings {
        var now = Date()
        var author = AssistantRestockReloadTests.ana
    }

    private func model(_ settings: Settings = Settings()) -> AssistantRestockModel {
        let model = AssistantRestockModel(
            context: context, container: nil, author: { settings.author }, saveDelay: .seconds(600),
            now: { settings.now }
        )
        model.load()
        return model
    }

    @Test("Another device's change redraws the tab on the next reload, as before")
    func changeElsewhereRedraws() throws {
        let paper = try AssistantRestockTestSupport.staple("Toilet Paper", in: context)
        try AssistantRestockTestSupport.staple("Paper Towels", in: context)
        let tab = model()

        // A note only: the shelf and the needs list stay the same objects.
        var before = tab.revision
        #expect(RestockService.setNote(paper, to: "Behind the sink"))
        #expect(context.safeSave())
        tab.load()
        #expect(tab.revision != before)

        before = tab.revision
        #expect(RestockService.setLevel(paper, to: .out, by: Self.guide, in: context))
        #expect(context.safeSave())
        tab.load()
        #expect(tab.revision != before)
        #expect(tab.officeRun.map(\.title) == ["Toilet Paper"])
    }

    @Test("A new day and a rename redraw the tab: times turn into dates, and who changed it reads anew")
    func dayAndNamesRedraw() throws {
        try AssistantRestockTestSupport.staple("Toilet Paper", level: .low, in: context)
        let settings = Settings()
        let tab = model(settings)

        var before = tab.revision
        settings.now = settings.now.addingTimeInterval(24 * 60 * 60)
        tab.load()
        #expect(tab.revision != before)

        before = tab.revision
        settings.author.name = "Ana B"
        tab.load()
        #expect(tab.revision != before)
    }

    @Test("A reload that finds nothing changed redraws nothing")
    func unchangedReloadIsQuiet() throws {
        try AssistantRestockTestSupport.staple("Toilet Paper", level: .low, in: context)
        try AssistantRestockTestSupport.staple("Paper Towels", place: "Sink", in: context)
        let tab = model()
        #expect(tab.officeRun.count == 1)
        let before = tab.revision

        let redrawn = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking {
            // What the tab's views read.
            _ = tab.shelf
            _ = tab.officeRun
            _ = tab.ordering
            _ = tab.officeRunCount
            _ = tab.revision
            _ = tab.guideName
            _ = tab.errorMessage
            for need in tab.officeRun { _ = tab.isCheckedOff(need) }
        } onChange: {
            redrawn.withLock { $0 = true }
        }

        tab.load()
        tab.load(reconcile: false)
        #expect(tab.revision == before)
        #expect(!redrawn.withLock { $0 })
    }

    @Test("Her own change always redraws, as before")
    func ownChangeRedraws() throws {
        let paper = try AssistantRestockTestSupport.staple("Toilet Paper", in: context)
        let tab = model()
        let before = tab.revision
        #expect(tab.tap(paper))
        #expect(tab.revision != before)
    }
}
