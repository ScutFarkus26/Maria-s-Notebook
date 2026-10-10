import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// The keys the calendar mirror files rows under (bug hunt 2026-10-10,
/// P2 #19-21): the same for one occurrence, and one calendar, on every device.
@Suite("EventKit mirror: occurrence and calendar keys")
@MainActor
struct EventKitMirrorKeyTests {

    @Test("Occurrence keys: an all-day day reads the same in any zone; a timed one is its UTC instant")
    func eventKeys() throws {
        let newYork = try #require(TimeZone(identifier: "America/New_York"))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = newYork
        let newYorkMidnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))
        calendar.timeZone = losAngeles
        let losAngelesMidnight = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 12)))

        let east = EventKitMirror.eventKey(
            externalIdentifier: "ABC", occurrenceDate: newYorkMidnight, isAllDay: true, timeZone: newYork
        )
        let west = EventKitMirror.eventKey(
            externalIdentifier: "ABC", occurrenceDate: losAngelesMidnight, isAllDay: true, timeZone: losAngeles
        )
        #expect(east == "x:ABC|2026-10-12")
        #expect(west == east)

        let timed = EventKitMirror.eventKey(
            externalIdentifier: "ABC", occurrenceDate: newYorkMidnight.addingTimeInterval(9 * 3_600), isAllDay: false,
            timeZone: losAngeles
        )
        #expect(timed == "x:ABC|2026-10-12T13:00:00Z")
    }

    @Test("Calendar keys: the same account and title on every device; Exchange names its platform")
    func calendarKeys() {
        func key(_ source: String, _ title: String, exchange: Bool, on platform: String) -> String {
            EventKitMirror.calendarKey(
                sourceTitle: source, calendarTitle: title, isExchange: exchange, platform: platform
            )
        }
        let onMac = key("iCloud", "School", exchange: false, on: "macOS")
        let onIPad = key("iCloud", "School", exchange: false, on: "iOS")
        #expect(onMac == "c:iCloud|School")
        #expect(onIPad == onMac)

        let exchangeMac = key("Work", "Calendar", exchange: true, on: "macOS")
        let exchangeIPad = key("Work", "Calendar", exchange: true, on: "iOS")
        #expect(exchangeMac != exchangeIPad)
    }
}

/// The calendar choice stays on each device; turning one off removes its rows
/// from the notebook at that moment (Decisions, 2026-10-10).
@Suite("Calendar sync: turning a calendar off")
@MainActor
struct CalendarSyncSelectionTests {

    @Test("Turning a calendar off removes its rows and keeps the others")
    func deselectingRemovesRows() throws {
        let suiteName = "calendar-selection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let school = "c:iCloud|School"
        let home = "c:iCloud|Home"
        defaults.set(["LOCAL-SCHOOL", "LOCAL-HOME"], forKey: UserDefaultsKeys.calendarSyncIdentifiers)
        // The keys this device synced each calendar under, School's from before a rename too.
        defaults.set(
            ["LOCAL-SCHOOL": ["c:iCloud|School (old)", school], "LOCAL-HOME": [home]],
            forKey: CalendarSyncService.calendarKeysDefaultsKey
        )
        let context = try CoreDataTestHelpers.makeContext()
        let rows = [("a", school, 0), ("b", school, -60), ("c", "c:iCloud|School (old)", -90), ("d", home, 1)]
        for (id, key, day) in rows {
            EventKitMirror.insertEvent(
                MirrorFixture.occurrence(id, day: day), calendarID: key, in: context, now: MirrorFixture.firstSync
            )
        }
        #expect(context.safeSave())
        let service = CalendarSyncService(context: context, defaults: defaults)

        service.updateSelection(identifiers: ["LOCAL-HOME"], names: ["Home"])

        #expect(!context.hasChanges)
        let left = context.safeFetch(CDFetchRequest(CDCalendarEvent.self)).compactMap(\.eventKitCalendarID)
        #expect(left == [home])
        #expect(service.syncCalendarIdentifiers == ["LOCAL-HOME"])
        let remembered = defaults.dictionary(forKey: CalendarSyncService.calendarKeysDefaultsKey) as? [String: [String]]
        #expect(remembered?["LOCAL-SCHOOL"] == nil)
        #expect(remembered?["LOCAL-HOME"] == [home])
    }
}
