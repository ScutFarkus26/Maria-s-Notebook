import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// The calendar mirror on several devices (bug hunt 2026-10-10, P2 #19–21).
/// Rows were keyed by one device's event identifier, which every occurrence
/// of a series shares and which differs on each device, so a weekly event
/// kept one row that jumped to its furthest occurrence, a calendar turned off
/// kept its rows for good, and two devices each added their own copy of every
/// event. Rows are now keyed the same way on every device; these tests sync
/// two simulated devices — each with its own local calendar identifier, as
/// EventKit gives every device — into one notebook.
@Suite("EventKit mirror: the same rows on every device")
@MainActor
struct EventKitMirrorDevicesTests {

    private typealias Fixture = MirrorFixture

    /// One device's calendar: the identifier EventKit gives it on that
    /// device, which the mirror must never store, and its cross-device key.
    /// `unsyncedCalendarKeys` are the device's other calendars.
    private struct SimulatedDevice {
        let localCalendarID: String
        let calendarKey: String
        var formerCalendarKeys: Set<String> = []
        var unsyncedCalendarKeys: Set<String> = []

        var fetch: EventKitMirror.CalendarFetch {
            EventKitMirror.CalendarFetch(
                calendarKeys: [calendarKey],
                formerCalendarKeys: formerCalendarKeys,
                unsyncedCalendarKeys: unsyncedCalendarKeys,
                localCalendarIDs: [localCalendarID],
                fallbackCalendarKey: calendarKey,
                windowStart: Fixture.schoolFetch.windowStart,
                windowEnd: Fixture.schoolFetch.windowEnd
            )
        }

        /// What EventKit on this device returns for `occurrences`: the
        /// server's identifiers, on this device's calendar.
        func events(_ occurrences: [(id: String, day: Int)], title: String = "Assembly") -> [CalendarEventSyncData] {
            occurrences.map { Fixture.occurrence($0.id, title: title, day: $0.day, calendar: calendarKey) }
        }

        @discardableResult
        func sync(
            _ events: [CalendarEventSyncData], into context: NSManagedObjectContext, now: Date = Fixture.secondSync
        ) -> EventKitMirror.Outcome {
            EventKitMirror.reconcileEvents(events, from: fetch, in: context, now: now)
        }
    }

    private static let schoolKey = EventKitMirror.calendarKey(
        sourceTitle: "iCloud", calendarTitle: "School", isExchange: false
    )
    private static let homeKey = EventKitMirror.calendarKey(
        sourceTitle: "iCloud", calendarTitle: "Home", isExchange: false
    )
    private let mac = SimulatedDevice(localCalendarID: "6A1F0C52-MAC", calendarKey: schoolKey)
    private let iPad = SimulatedDevice(localCalendarID: "E93B7D10-IPAD", calendarKey: schoolKey)

    private static func rows(in context: NSManagedObjectContext) -> [CDCalendarEvent] {
        context.safeFetch(CDFetchRequest(CDCalendarEvent.self))
    }

    // MARK: - Occurrences

    @Test("A weekly series keeps one row per occurrence, and a moved occurrence keeps its row")
    func weeklySeriesKeepsEveryOccurrence() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let weeks = [0, 7, 14, 21].map { (id: "weekly-series", day: $0) }

        let first = mac.sync(mac.events(weeks), into: context, now: Fixture.firstSync)
        #expect(first == EventKitMirror.Outcome(inserted: 4))
        #expect(context.safeSave())
        let starts = Set(Self.rows(in: context).compactMap(\.startDate))
        #expect(starts == Set(weeks.map { Fixture.firstSync.addingTimeInterval(TimeInterval($0.day * 86_400)) }))

        // The third week moves a day later: same occurrence, so the same row.
        var events = mac.events(weeks)
        events[2] = Fixture.occurrence(
            "weekly-series", title: "Assembly", day: 15, occurrenceDay: 14, calendar: mac.calendarKey
        )
        let second = mac.sync(events, into: context)
        #expect(second == EventKitMirror.Outcome(updated: 1))
        let moved = try #require(Fixture.eventRows(in: context)[Fixture.key("weekly-series", day: 14)])
        #expect(moved.startDate == Fixture.firstSync.addingTimeInterval(15 * 86_400))
        #expect(Self.rows(in: context).count == 4)
    }

    // MARK: - Two devices

    @Test("Two devices with different local calendar IDs sync into the same rows")
    func twoDevicesShareRows() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let occurrences = [(id: "assembly", day: 0), (id: "weekly-series", day: 1), (id: "weekly-series", day: 8)]

        #expect(mac.sync(mac.events(occurrences), into: context) == EventKitMirror.Outcome(inserted: 3))
        #expect(context.safeSave())
        // The iPad sees the same events from the server: nothing to add, change or delete.
        #expect(iPad.sync(iPad.events(occurrences), into: context) == EventKitMirror.Outcome())
        #expect(!context.hasChanges)

        // A change made on either device is one update to the shared row; the other then has nothing to do.
        let renamed = iPad.events(occurrences, title: "Assembly in the hall")
        #expect(iPad.sync(renamed, into: context) == EventKitMirror.Outcome(updated: 3))
        #expect(context.safeSave())
        let seenOnMac = mac.events(occurrences, title: "Assembly in the hall")
        #expect(mac.sync(seenOnMac, into: context) == EventKitMirror.Outcome())

        let rows = Self.rows(in: context)
        #expect(rows.count == 3)
        #expect(rows.allSatisfy { $0.eventKitCalendarID == Self.schoolKey })
        let storedStrings = rows.flatMap { [$0.eventKitEventID ?? "", $0.eventKitCalendarID ?? ""] }
        #expect(!storedStrings.contains { $0.contains(mac.localCalendarID) || $0.contains(iPad.localCalendarID) })
    }

    @Test("Copies two devices add at once fold to one row per occurrence, then stay put")
    func simultaneousCopiesConverge() throws {
        let macContext = try CoreDataTestHelpers.makeContext()
        let iPadContext = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        iPadContext.persistentStoreCoordinator = macContext.persistentStoreCoordinator
        let occurrences = [(id: "assembly", day: 0), (id: "weekly-series", day: 1), (id: "weekly-series", day: 8)]

        // Each device inserts before the other's rows arrive.
        #expect(mac.sync(mac.events(occurrences), into: macContext) == EventKitMirror.Outcome(inserted: 3))
        #expect(iPad.sync(iPad.events(occurrences), into: iPadContext) == EventKitMirror.Outcome(inserted: 3))
        #expect(macContext.safeSave())
        #expect(iPadContext.safeSave())
        #expect(Self.rows(in: macContext).count == 6)

        // Both devices keep both copies current without deleting either...
        #expect(mac.sync(mac.events(occurrences), into: macContext) == EventKitMirror.Outcome())
        #expect(iPad.sync(iPad.events(occurrences), into: iPadContext) == EventKitMirror.Outcome())

        // ...until the dedup pass folds them by key and start.
        #expect(DataCleanupService.mergeSameEventKitEvents(using: macContext, container: nil) == 3)
        let keys = Self.rows(in: macContext).compactMap(\.eventKitEventID)
        #expect(keys.count == 3)
        #expect(Set(keys).count == 3)
        #expect(mac.sync(mac.events(occurrences), into: macContext) == EventKitMirror.Outcome())
        #expect(iPad.sync(iPad.events(occurrences), into: macContext) == EventKitMirror.Outcome())
        #expect(!macContext.hasChanges)
    }

    @Test("A device never deletes or rewrites rows of a calendar it has but doesn't sync")
    func otherDevicesCalendarIsLeftAlone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let homeOnly = SimulatedDevice(
            localCalendarID: "B4-HOME", calendarKey: Self.homeKey, unsyncedCalendarKeys: [Self.schoolKey]
        )
        mac.sync(mac.events([(id: "assembly", day: 0), (id: "fire-drill", day: 2)]), into: context)
        #expect(context.safeSave())

        // The iPad syncs only Home. It sees nothing of School inside the same
        // window, and one School event also sits on its Home calendar (an
        // invitation to it) with its own copy of the title.
        let invitation = Fixture.occurrence("assembly", title: "Assembly (invited)", calendar: Self.homeKey)
        let dentist = Fixture.occurrence("dentist", day: 1, calendar: Self.homeKey)
        let outcome = homeOnly.sync([invitation, dentist], into: context)
        #expect(outcome == EventKitMirror.Outcome(inserted: 1))

        let rows = Fixture.eventRows(in: context)
        let assembly = try #require(rows[Fixture.key("assembly")])
        #expect(assembly.eventKitCalendarID == Self.schoolKey)
        #expect(assembly.title == "Assembly")
        #expect(rows[Fixture.key("fire-drill", day: 2)] != nil)
        #expect(rows[Fixture.key("dentist", day: 1)]?.eventKitCalendarID == Self.homeKey)
    }

    @Test("Old-format rows are re-keyed in place; history and other devices' rows stay")
    func oldFormatRowsAreRekeyedInPlace() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // What each device stored before: its own event identifiers and its
        // own local calendar identifier.
        func oldRow(_ eventID: String, on calendarID: String, title: String = "Assembly", day: Int) -> CDCalendarEvent {
            let row = EventKitMirror.insertEvent(
                Fixture.occurrence("unused", title: title, day: day), calendarID: calendarID,
                in: context, now: Fixture.firstSync
            )
            row.eventKitEventID = eventID
            return row
        }
        let macCopy = oldRow("6A1F0C52-MAC:EV-1", on: mac.localCalendarID, day: 0)
        let iPadCopy = oldRow("E93B7D10-IPAD:EV-1", on: iPad.localCalendarID, day: 0)
        let history = oldRow("6A1F0C52-MAC:EV-OLD", on: mac.localCalendarID, day: -40)
        let deletedSince = oldRow("6A1F0C52-MAC:EV-GONE", on: mac.localCalendarID, title: "Fire drill", day: 2)
        let otherDevice = oldRow("B4:EV-9", on: "B4-HOME", title: "Dentist", day: 1)
        #expect(context.safeSave())

        let assembly = Fixture.occurrence("assembly", localID: "6A1F0C52-MAC:EV-1", calendar: mac.calendarKey)
        let outcome = mac.sync([assembly], into: context)

        // Both old copies of the assembly take its key (the Mac's by its own
        // identifier, the iPad's by title and time); nothing is inserted.
        #expect(outcome == EventKitMirror.Outcome(updated: 2, deleted: 1))
        for copy in [macCopy, iPadCopy] {
            #expect(!copy.isDeleted)
            #expect(copy.eventKitEventID == Fixture.key("assembly"))
            #expect(copy.eventKitCalendarID == Self.schoolKey)
        }
        // A Mac row whose event is gone from the Mac's calendar goes.
        #expect(deletedSince.isDeleted)
        // History outside the window, and another device's row, stay as they were.
        #expect(!history.isDeleted && history.eventKitEventID == "6A1F0C52-MAC:EV-OLD")
        #expect(!otherDevice.isDeleted && otherDevice.eventKitEventID == "B4:EV-9")
        #expect(context.safeSave())

        // The dedup pass folds the two copies; after that, syncs write nothing.
        #expect(DataCleanupService.mergeSameEventKitEvents(using: context, container: nil) == 1)
        #expect(mac.sync([assembly], into: context) == EventKitMirror.Outcome())
        #expect(!context.hasChanges)
        #expect(Self.rows(in: context).count == 3)
    }

    @Test("Two devices whose account titles differ keep one set of rows and never trade deletes")
    func differingAccountTitlesShareRows() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // One Google calendar, whose account the Mac and the iPad name differently.
        let macGoogle = SimulatedDevice(
            localCalendarID: "6A1F0C52-GOOGLE",
            calendarKey: EventKitMirror.calendarKey(sourceTitle: "Google", calendarTitle: "School", isExchange: false)
        )
        let iPadGoogle = SimulatedDevice(
            localCalendarID: "E93B7D10-GOOGLE",
            calendarKey: EventKitMirror.calendarKey(
                sourceTitle: "danny@example.com", calendarTitle: "School", isExchange: false
            )
        )
        let weeks = [0, 7, 14].map { (id: "weekly-series", day: $0) }
        let single = (id: "assembly", day: 2)
        let firstSync = macGoogle.sync(macGoogle.events(weeks + [single]), into: context)
        #expect(firstSync == EventKitMirror.Outcome(inserted: 4))
        #expect(context.safeSave())

        // The iPad adds nothing of its own, and keeps the Mac's rows current.
        #expect(iPadGoogle.sync(iPadGoogle.events(weeks + [single]), into: context) == EventKitMirror.Outcome())
        let renamed = iPadGoogle.events(weeks, title: "Assembly in the hall") + iPadGoogle.events([single])
        #expect(iPadGoogle.sync(renamed, into: context) == EventKitMirror.Outcome(updated: 3))
        #expect(context.safeSave())
        #expect(Self.rows(in: context).allSatisfy { $0.eventKitCalendarID == macGoogle.calendarKey })
        let macRenamed = macGoogle.events(weeks, title: "Assembly in the hall") + macGoogle.events([single])
        #expect(macGoogle.sync(macRenamed, into: context) == EventKitMirror.Outcome())

        // One week is cancelled and the single event is deleted. The iPad still
        // sees the series, so it knows that week is gone; the single event it
        // can't tell from one only the Mac has, so it leaves it to the Mac.
        let afterCancelling = iPadGoogle.events([weeks[0], weeks[2]], title: "Assembly in the hall")
        #expect(iPadGoogle.sync(afterCancelling, into: context) == EventKitMirror.Outcome(deleted: 1))
        #expect(context.safeSave())
        #expect(Fixture.eventRows(in: context)[Fixture.key("assembly", day: 2)] != nil)
        let macAfter = macGoogle.events([weeks[0], weeks[2]], title: "Assembly in the hall")
        #expect(macGoogle.sync(macAfter, into: context) == EventKitMirror.Outcome(deleted: 1))
        #expect(context.safeSave())
        #expect(Self.rows(in: context).count == 2)
        #expect(iPadGoogle.sync(afterCancelling, into: context) == EventKitMirror.Outcome())
    }

    // MARK: - Calendars changing

    @Test("Turning a calendar off removes all its rows once; a device still syncing it adds its window back")
    func removingACalendarIsOneDelete() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let homeOnly = SimulatedDevice(localCalendarID: "B4-HOME", calendarKey: Self.homeKey)
        mac.sync(mac.events([(id: "assembly", day: 0), (id: "history", day: -30)]), into: context)
        homeOnly.sync(homeOnly.events([(id: "dentist", day: 1)]), into: context)
        #expect(context.safeSave())

        #expect(EventKitMirror.removeEvents(inCalendars: [Self.schoolKey], in: context) == 2)
        #expect(context.safeSave())
        #expect(Self.rows(in: context).map(\.eventKitCalendarID) == [Self.homeKey])

        // The iPad still syncs School, so its next sync brings back its window.
        let refetched = iPad.sync(iPad.events([(id: "assembly", day: 0)]), into: context)
        #expect(refetched == EventKitMirror.Outcome(inserted: 1))
    }

    @Test("A renamed calendar's rows follow it; one deleted meanwhile goes")
    func renamedCalendarKeepsItsRows() throws {
        let context = try CoreDataTestHelpers.makeContext()
        mac.sync(mac.events([(id: "assembly", day: 0), (id: "fire-drill", day: 2)]), into: context)
        #expect(context.safeSave())

        let renamedKey = EventKitMirror.calendarKey(
            sourceTitle: "iCloud", calendarTitle: "School 2026", isExchange: false
        )
        let renamed = SimulatedDevice(
            localCalendarID: mac.localCalendarID, calendarKey: renamedKey, formerCalendarKeys: [Self.schoolKey]
        )
        let outcome = renamed.sync(renamed.events([(id: "assembly", day: 0)]), into: context)
        #expect(outcome == EventKitMirror.Outcome(updated: 1, deleted: 1))
        let rows = Self.rows(in: context)
        #expect(rows.count == 1)
        #expect(rows.first?.eventKitCalendarID == renamedKey)
    }

    @Test("An event on two of this device's calendars is one row, on the same calendar every time")
    func eventOnTwoCalendarsIsOneRow() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let both = EventKitMirror.CalendarFetch(
            calendarKeys: [Self.schoolKey, Self.homeKey],
            fallbackCalendarKey: Self.schoolKey,
            windowStart: Fixture.schoolFetch.windowStart,
            windowEnd: Fixture.schoolFetch.windowEnd
        )
        let events = [
            Fixture.occurrence("assembly", calendar: Self.schoolKey),
            Fixture.occurrence("assembly", calendar: Self.homeKey)
        ]
        #expect(EventKitMirror.reconcileEvents(events, from: both, in: context, now: Fixture.firstSync)
            == EventKitMirror.Outcome(inserted: 1))
        #expect(Self.rows(in: context).first?.eventKitCalendarID == Self.homeKey)
        #expect(EventKitMirror.reconcileEvents(events.reversed(), from: both, in: context, now: Fixture.secondSync)
            == EventKitMirror.Outcome())
    }
}
