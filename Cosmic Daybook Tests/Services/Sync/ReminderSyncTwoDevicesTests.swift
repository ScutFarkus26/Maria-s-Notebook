import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// Reminders sync on two devices at once (Simplify the app, Phase 9). EventKit
/// gives every device its own identifier for the list and for each reminder in
/// it, so each device keeps its own rows, and Today shows only the rows of this
/// device's list. These tests sync a simulated Mac and iPad, each with its own
/// context on one notebook (iCloud), through restored copies with no links:
/// neither Today may ever show a reminder twice, and every copy ends linked.
@Suite("Reminders on two devices")
@MainActor
struct ReminderSyncTwoDevicesTests {

    private typealias Fixture = MirrorFixture

    /// One device: its list identifier, and its own context on the notebook.
    private struct Device {
        let name: String
        let context: NSManagedObjectContext

        var listID: String { "\(name)-list" }

        /// What EventKit on this device returns for `titles`: this device's
        /// own identifier for each.
        func reminders(_ titles: [String]) -> [ReminderSyncData] {
            titles.map { title in
                UnlinkedReminderFixture.reminder("\(name)-\(title)", title: title, due: Fixture.dueSoon, modified: Fixture.firstSync)
            }
        }

        @discardableResult
        func sync(_ titles: [String], now: Date = Fixture.secondSync) -> EventKitMirror.Outcome {
            EventKitMirror.reconcileReminders(reminders(titles), listID: listID, in: context, now: now)
        }

        /// The titles Today lists here: open rows of this device's list, the
        /// query `TodayDataFetcher.fetchReminders` makes.
        func today() -> [String] {
            let request = CDFetchRequest(CDReminder.self)
            request.predicate = NSPredicate(format: "isCompleted == NO AND eventKitCalendarID == %@", listID)
            return context.safeFetch(request).map(\.title).sorted()
        }

        /// iCloud brings in what the other device saved.
        func receive() {
            context.refreshAllObjects()
        }
    }

    private let mac: Device
    private let iPad: Device

    init() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let iPadContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        iPadContext.persistentStoreCoordinator = stack.viewContext.persistentStoreCoordinator
        // The app's policy: the later save wins, field by field, as iCloud keeps the last change.
        for context in [stack.viewContext, iPadContext] {
            context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        }
        mac = Device(name: "mac", context: stack.viewContext)
        iPad = Device(name: "ipad", context: iPadContext)
    }

    /// Restored copies with no links, in the shared notebook.
    @discardableResult
    private func restoredCopies(_ titles: [String], created: [Date]? = nil) -> [CDReminder] {
        let copies = titles.enumerated().map { index, title in
            let row = CDReminder(context: mac.context)
            row.title = title
            row.dueDate = Fixture.dueSoon.date
            row.createdAt = created?[index] ?? Fixture.firstSync
            return row
        }
        #expect(mac.context.safeSave())
        iPad.receive()
        return copies
    }

    private func allRows() -> [CDReminder] {
        mac.context.safeFetch(CDFetchRequest(CDReminder.self))
    }

    @Test("After a restore, both devices sync the same list: one row each per reminder, never a double on Today")
    func bothDevicesSyncAfterRestore() {
        let titles = ["Call Ms. Levin", "Order paint"]
        restoredCopies(titles)

        #expect(mac.sync(titles) == EventKitMirror.Outcome(updated: 2))
        #expect(mac.context.safeSave())
        #expect(mac.today() == titles)

        iPad.receive()
        // The copies are the Mac's now; the iPad files the list under its own rows.
        #expect(iPad.sync(titles) == EventKitMirror.Outcome(inserted: 2))
        #expect(iPad.context.safeSave())
        #expect(iPad.today() == titles)

        mac.receive()
        #expect(mac.sync(titles, now: Fixture.thirdSync) == EventKitMirror.Outcome())
        #expect(mac.today() == titles)
        #expect(allRows().count == 4)
        #expect(allRows().allSatisfy { $0.eventKitReminderID != nil })

        // A reminder deleted in Reminders goes from each device's rows as that device syncs,
        // and no device deletes the other's.
        #expect(iPad.sync(["Call Ms. Levin"], now: Fixture.thirdSync) == EventKitMirror.Outcome(deleted: 1))
        #expect(iPad.context.safeSave())
        mac.receive()
        #expect(mac.today() == titles)
        #expect(mac.sync(["Call Ms. Levin"], now: Fixture.thirdSync) == EventKitMirror.Outcome(deleted: 1))
        #expect(mac.context.safeSave())
        iPad.receive()
        #expect(mac.today() == ["Call Ms. Levin"])
        #expect(iPad.today() == ["Call Ms. Levin"])
        #expect(allRows().count == 2)
    }

    @Test("Two devices that take over the same copy at once settle on one row each")
    func simultaneousTakeOverSettles() throws {
        let copy = try #require(restoredCopies(["Order paint"]).first)

        // Each takes the copy over before the other's change arrives.
        #expect(mac.sync(["Order paint"]) == EventKitMirror.Outcome(updated: 1))
        #expect(iPad.sync(["Order paint"]) == EventKitMirror.Outcome(updated: 1))
        #expect(mac.today() == ["Order paint"])
        #expect(iPad.today() == ["Order paint"])
        #expect(mac.context.safeSave())
        #expect(iPad.context.safeSave())

        // The iPad saved last, so the copy holds its link; the Mac's Today misses the
        // reminder until its next sync gives it a row of its own.
        mac.receive()
        #expect(copy.eventKitReminderID == "ipad-Order paint")
        #expect(copy.eventKitCalendarID == iPad.listID)
        #expect(mac.today().isEmpty)
        #expect(mac.sync(["Order paint"], now: Fixture.thirdSync) == EventKitMirror.Outcome(inserted: 1))
        #expect(mac.context.safeSave())
        iPad.receive()

        #expect(mac.today() == ["Order paint"])
        #expect(iPad.today() == ["Order paint"])
        #expect(allRows().count == 2)
        #expect(Set(allRows().compactMap(\.eventKitCalendarID)) == [mac.listID, iPad.listID])
        // Both settled: another round changes nothing on either.
        #expect(mac.sync(["Order paint"], now: Fixture.thirdSync) == EventKitMirror.Outcome())
        #expect(iPad.sync(["Order paint"], now: Fixture.thirdSync) == EventKitMirror.Outcome())
    }

    @Test("When the backup held each device's copy, the device that lost the race takes the other one")
    func lostRaceTakesTheOtherCopy() throws {
        let older = Fixture.firstSync.addingTimeInterval(-0.5)
        let copies = restoredCopies(["Order paint", "Order paint"], created: [older, Fixture.firstSync])

        // Both rank the copies the same way and take the older one at once.
        mac.sync(["Order paint"])
        iPad.sync(["Order paint"])
        #expect(mac.context.safeSave())
        #expect(iPad.context.safeSave())
        mac.receive()
        #expect(copies[0].eventKitReminderID == "ipad-Order paint")
        #expect(copies[1].eventKitReminderID == nil)

        // The Mac takes the copy that's left rather than adding a row.
        #expect(mac.sync(["Order paint"], now: Fixture.thirdSync) == EventKitMirror.Outcome(updated: 1))
        #expect(mac.context.safeSave())
        iPad.receive()
        #expect(copies[1].eventKitReminderID == "mac-Order paint")
        #expect(mac.today() == ["Order paint"])
        #expect(iPad.today() == ["Order paint"])
        #expect(allRows().count == 2)
    }
}
