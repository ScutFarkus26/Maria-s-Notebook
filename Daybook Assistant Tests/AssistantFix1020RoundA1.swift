import AppIntents
import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The code review of the 2026-10-20 bug-hunt fixes, items 4-8: Siri's App
// Shortcut phrases and sound-alike names (4), a stale "Couldn't save" after a
// save made on another tab (5), a merged need's note written twice (6), "We
// need…" naming a staple the guide just deleted (7), and the school-day
// count reading a notebook of her own on the same Apple Account (8).
@Suite("Assistant review fixes (Fix1020 RoundA1)")
@MainActor
struct AssistantFix1020RoundA1Tests {

    private let stack: CoreDataStack

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    // MARK: - 4 Sound-alike names as synonyms

    @Test("Sound-alike first names carry each other's spelling, so a phrase finds both and Siri asks")
    func soundAlikeSynonyms() throws {
        let saraK = AssistantTestSupport.student("Sara", "Klein", in: context)
        let sarahA = AssistantTestSupport.student("Sarah", "Adler", in: context)
        let sarahB = AssistantTestSupport.student("Sarah", "Brook", in: context)
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        #expect(context.safeSave())

        let ids = [saraK, sarahA, sarahB, maya].compactMap(\.id)
        let entities = StudentEntityQuery.entities(for: ids, in: context)
        func synonyms(_ student: CDStudent) throws -> [String] {
            let entity = try #require(entities.first { $0.id == student.id })
            return entity.displayRepresentation.synonyms.map { String(localized: $0) }
        }

        #expect(try synonyms(saraK) == ["Sara", "Sara K", "Sarah"])
        // The other Sarah's spelling is her own: nothing more to add.
        #expect(try synonyms(sarahA) == ["Sarah", "Sarah A", "Sara"])
        #expect(try synonyms(sarahB) == ["Sarah", "Sarah B", "Sara"])
        #expect(try synonyms(maya) == ["Maya", "Maya S"])
    }

    @Test("Names that only look alike get nothing: Bet and Beth sound different")
    func lookAlikesGetNothing() throws {
        let bet = AssistantTestSupport.student("Bet", "Ross", in: context)
        let beth = AssistantTestSupport.student("Beth", "Cole", in: context)
        #expect(context.safeSave())

        let entities = StudentEntityQuery.entities(for: [bet, beth].compactMap(\.id), in: context)
        let synonyms = Dictionary(uniqueKeysWithValues: entities.map { entity in
            (entity.firstName, entity.displayRepresentation.synonyms.map { String(localized: $0) })
        })
        #expect(synonyms["Bet"] == ["Bet", "Bet R"])
        #expect(synonyms["Beth"] == ["Beth", "Beth C"])
    }

    // MARK: - 5 A stale save banner

    /// A save that fails until told to work.
    final class FailingSave {
        var fails = true

        func save(_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool {
            fails ? false : context.safeSave()
        }
    }

    @Test("Back on the tab, a save that worked on another tab clears Couldn't save")
    func appearingClearsStaleBanner() throws {
        let towels = try AssistantRestockTestSupport.staple("Paper Towels", in: context)
        let failing = FailingSave()
        let tab = AssistantRestockTestSupport.model(in: context, save: failing.save)
        tab.tap(towels)
        #expect(!tab.flush())
        #expect(tab.errorMessage != nil)

        // Off the tab, the attendance grid saves the same context, and it works now.
        failing.fails = false
        #expect(context.safeSave())
        #expect(tab.errorMessage != nil)

        tab.appeared()
        #expect(tab.errorMessage == nil)
    }

    // MARK: - 6 A merged note, once

    private func need(
        for staple: CDSupply, created: Date, notes: String
    ) throws -> CDOrderItem {
        let item = CDOrderItem(context: context)
        item.title = staple.name
        item.source = .office
        item.supplyID = try #require(staple.id?.uuidString)
        item.createdAt = created
        item.modifiedAt = created
        item.quantity = 1
        item.notes = notes
        return item
    }

    @Test("Merging needs keeps each note once, when the kept one already joined some")
    func mergeKeepsEachNoteOnce() throws {
        let towels = try AssistantRestockTestSupport.staple("Paper Towels", in: context)
        let older = try need(
            for: towels, created: Date(timeIntervalSince1970: 10), notes: "The big rolls · From the closet"
        )
        _ = try need(for: towels, created: Date(timeIntervalSince1970: 20), notes: "From the closet")
        #expect(context.safeSave())

        #expect(RestockService.reconcile(in: context) == 1)
        #expect(older.notes == "The big rolls · From the closet")
        #expect(older.modifiedAt == Date(timeIntervalSince1970: 10), "copies that agree change nothing")
    }

    @Test("A going copy's joined notes add only what the kept one lacks")
    func mergeSplitsGoingNotes() throws {
        let towels = try AssistantRestockTestSupport.staple("Paper Towels", in: context)
        let older = try need(for: towels, created: Date(timeIntervalSince1970: 10), notes: "The big rolls")
        _ = try need(for: towels, created: Date(timeIntervalSince1970: 20), notes: "From the closet · The big rolls")
        #expect(context.safeSave())

        #expect(RestockService.reconcile(in: context) == 1)
        #expect(older.notes == "The big rolls · From the closet")
    }

    // MARK: - 7 We need… a staple that's gone

    @Test("We need… naming a staple the guide just deleted adds it as a one-off")
    func weNeedDeletedStapleIsOneOff() throws {
        let towels = try AssistantRestockTestSupport.staple("Paper Towels", in: context)
        let tab = AssistantRestockTestSupport.model(in: context)
        // Deleted while the sheet is up (the guide's delete arriving).
        context.delete(towels)
        #expect(tab.staple(named: "Paper Towels") == nil)

        #expect(tab.addNeed("Paper Towels", source: .office, quantity: 2) == .added)
        let needs = RestockService.openNeeds(in: context)
        #expect(needs.count == 1)
        #expect(needs.first?.title == "Paper Towels")
        #expect(needs.first?.quantity == 2)
        #expect(needs.first?.supplyID == nil)
    }
}

// MARK: - 8 The school-day count from the classroom share only

@Suite("Assistant school-day count on two stores (Fix1020 RoundA1)")
@MainActor
struct AssistantSchoolDayCountSplitStoreTests {

    typealias Count = AttendanceSchoolDayCount

    /// Private and shared SQLite stores in a temporary folder, as on a phone.
    private func splitContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            _ = try coordinator.addPersistentStore(
                type: .sqlite, configuration: configuration,
                at: dir.appendingPathComponent("\(configuration).sqlite")
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func store(_ configuration: String, in context: NSManagedObjectContext) throws -> NSPersistentStore {
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        return try #require(stores.first { $0.configurationName == configuration })
    }

    private func day(_ iso: String) throws -> Date {
        try AssistantTestSupport.day(iso)
    }

    @Test("A notebook of her own on the same Apple Account moves neither First Day nor the count")
    func privateStoreStaysOut() throws {
        let context = try splitContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        let mine = try store(CoreDataStack.privateConfiguration, in: context)
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        context.assign(ari, to: shared)
        let ariID = try #require(ari.id?.uuidString)

        // The class's first mark: Tuesday, Sep 1, 2026.
        let classMark = CDAttendanceRecord(context: context)
        classMark.studentID = ariID
        classMark.date = try day("2026-09-01")
        classMark.status = .present
        context.assign(classMark, to: shared)
        // Her own notebook: an earlier mark and a day off of its own.
        let ownMark = CDAttendanceRecord(context: context)
        ownMark.studentID = ariID
        ownMark.date = try day("2026-08-25")
        ownMark.status = .present
        context.assign(ownMark, to: mine)
        let ownDayOff = CDNonSchoolDay(context: context)
        ownDayOff.date = try day("2026-09-02")
        ownDayOff.reason = "Her own day off"
        context.assign(ownDayOff, to: mine)
        // The class's own day off still counts.
        let classDayOff = CDNonSchoolDay(context: context)
        classDayOff.date = try day("2026-09-04")
        classDayOff.reason = "Staff day"
        context.assign(classDayOff, to: shared)
        #expect(context.safeSave())

        let first = try #require(Count.firstDay(inYearStarting: try day("2026-07-01"), in: context))
        #expect(first == (try day("2026-09-01")))
        #expect(Count.number(of: try day("2026-09-03"), firstDay: first, in: context) == 3)
        #expect(Count.number(of: try day("2026-09-04"), firstDay: first, in: context) == nil)
    }
}
