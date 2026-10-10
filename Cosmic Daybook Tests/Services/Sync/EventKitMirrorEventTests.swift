import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the calendar mirror's write rule (Danny, 2026-09-25): a sync writes a
/// row, and stamps `lastSyncedAt`, only when the row is new or a value copied
/// from EventKit changed; every copied value still ends up exactly as the old
/// copy left it. EventKit can't run here, so the tests hand `EventKitMirror`
/// the values a sync would.
@Suite("EventKit mirrors: calendar events")
@MainActor
struct EventKitMirrorEventTests {

    private typealias Fixture = MirrorFixture

    @Test("A second sync over unchanged events leaves nothing to save and no history")
    func unchangedEventsWriteNothing() throws {
        let store = try HistoryStoreFixture()
        defer { store.cleanUp() }
        let context = store.stack.viewContext
        let events = [
            Fixture.occurrence("e1"),
            Fixture.occurrence("e2", title: "Field trip", day: 3, location: nil, notes: "Bring lunch"),
            Fixture.occurrence("e3", day: 10, allDay: true)
        ]

        let first = EventKitMirror.reconcileEvents(
            events, from: Fixture.schoolFetch, in: context, now: Fixture.firstSync
        )
        #expect(first == EventKitMirror.Outcome(inserted: 3))
        #expect(context.safeSave())
        let token = try store.historyToken()

        let second = EventKitMirror.reconcileEvents(
            events, from: Fixture.schoolFetch, in: context, now: Fixture.secondSync
        )
        #expect(second == EventKitMirror.Outcome())
        #expect(!context.hasChanges)
        #expect(context.safeSave())
        #expect(try store.transactions(after: token).isEmpty)
        let stamps = Set(Fixture.eventRows(in: context).values.map(\.lastSyncedAt))
        #expect(stamps == [Fixture.firstSync])
    }

    @Test("A changed event rewrites only its row and stamps it; a new event is stamped")
    func changedEventRewritesOnlyItsRow() throws {
        let context = try CoreDataTestHelpers.makeContext()
        EventKitMirror.reconcileEvents(
            [Fixture.occurrence("e1"), Fixture.occurrence("e2")],
            from: Fixture.schoolFetch, in: context, now: Fixture.firstSync
        )
        #expect(context.safeSave())

        let moved = Fixture.occurrence("e2", title: "Assembly (moved)", day: 1, occurrenceDay: 0)
        let outcome = EventKitMirror.reconcileEvents(
            [Fixture.occurrence("e1"), moved, Fixture.occurrence("e3", day: 2)],
            from: Fixture.schoolFetch, in: context, now: Fixture.secondSync
        )
        #expect(outcome == EventKitMirror.Outcome(inserted: 1, updated: 1))
        let rows = Fixture.eventRows(in: context)
        let changed = try #require(rows[Fixture.key("e2")])
        let unchanged = try #require(rows[Fixture.key("e1")])
        let added = try #require(rows[Fixture.key("e3", day: 2)])
        #expect(context.updatedObjects.count == 1)
        #expect(context.updatedObjects.contains(changed))
        #expect(changed.title == "Assembly (moved)")
        #expect(changed.startDate == moved.startDate)
        #expect(changed.lastSyncedAt == Fixture.secondSync)
        #expect(unchanged.lastSyncedAt == Fixture.firstSync)
        #expect(added.lastSyncedAt == Fixture.secondSync)
        #expect(added.eventKitCalendarID == "cal-school")
    }

    // Until 2026-10-10 a stored recurring event kept one row, which ended on
    // its last occurrence (bug hunt 2026-10-10, P2 #19).
    @Test("A stored recurring event gains a row for each new occurrence and keeps the first")
    func storedRecurringEventKeepsEveryOccurrence() throws {
        let context = try CoreDataTestHelpers.makeContext()
        EventKitMirror.reconcileEvents(
            [Fixture.occurrence("weekly")], from: Fixture.schoolFetch, in: context, now: Fixture.firstSync
        )
        #expect(context.safeSave())
        let occurrences = [0, 7, 14].map { Fixture.occurrence("weekly", day: $0) }

        let second = EventKitMirror.reconcileEvents(
            occurrences, from: Fixture.schoolFetch, in: context, now: Fixture.secondSync
        )
        #expect(second == EventKitMirror.Outcome(inserted: 2))
        let first = try #require(Fixture.eventRows(in: context)[Fixture.key("weekly")])
        #expect(first.startDate == occurrences[0].startDate)
        #expect(first.lastSyncedAt == Fixture.firstSync)
        #expect(context.safeSave())

        let third = EventKitMirror.reconcileEvents(
            occurrences, from: Fixture.schoolFetch, in: context, now: Fixture.thirdSync
        )
        #expect(third == EventKitMirror.Outcome())
        #expect(!context.hasChanges)
    }

    @Test("A new recurring event inserts a row per occurrence, each on its own calendar")
    func newRecurringEventInsertsPerOccurrence() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let occurrences = [
            Fixture.occurrence("weekly", calendar: "cal-home"),
            Fixture.occurrence("weekly", day: 7, calendar: "cal-other"),
            Fixture.occurrence("unfiled", day: 1, calendar: nil)
        ]

        let outcome = EventKitMirror.reconcileEvents(
            occurrences, from: Fixture.schoolFetch, in: context, now: Fixture.firstSync
        )
        #expect(outcome == EventKitMirror.Outcome(inserted: 3))
        let rows = context.safeFetch(CDFetchRequest(CDCalendarEvent.self))
        let weekly = rows.filter { [Fixture.key("weekly"), Fixture.key("weekly", day: 7)].contains($0.eventKitEventID) }
        let unfiled = try #require(rows.first { $0.eventKitEventID == Fixture.key("unfiled", day: 1) })
        #expect(weekly.count == 2)
        #expect(Set(weekly.compactMap(\.eventKitCalendarID)) == ["cal-home", "cal-other"])
        #expect(unfiled.eventKitCalendarID == "cal-school")
    }

    @Test("An event gone from EventKit is deleted only inside the fetched window and calendars")
    func deletionKeepsItsScope() throws {
        let context = try CoreDataTestHelpers.makeContext()
        EventKitMirror.reconcileEvents(
            [Fixture.occurrence("kept"), Fixture.occurrence("gone", day: 1), Fixture.occurrence("history", day: -20)],
            from: Fixture.schoolFetch, in: context, now: Fixture.firstSync
        )
        EventKitMirror.insertEvent(
            Fixture.occurrence("elsewhere", day: 2), calendarID: "cal-other", in: context, now: Fixture.firstSync
        )
        #expect(context.safeSave())

        let outcome = EventKitMirror.reconcileEvents(
            [Fixture.occurrence("kept")], from: Fixture.schoolFetch, in: context, now: Fixture.secondSync
        )
        #expect(outcome == EventKitMirror.Outcome(deleted: 1))
        let expected = [Fixture.key("kept"), Fixture.key("history", day: -20), Fixture.key("elsewhere", day: 2)]
        #expect(Set(Fixture.eventRows(in: context).keys) == Set(expected))
    }

    @Test("Each copied field ends exactly as the old copy wrote it")
    func updateMatchesOldCopy() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = Fixture.occurrence("e1", title: "Caf\u{E9} meeting", location: nil, notes: "Agenda")
        let incoming = [
            stored,
            Fixture.occurrence("e1", title: "Cafe\u{301} meeting", location: nil, notes: "Agenda"),
            Fixture.occurrence("e1", title: "Caf\u{E9} meeting", location: "", notes: "Agenda"),
            Fixture.occurrence("e1", title: "Caf\u{E9} meeting", location: nil, notes: nil),
            Fixture.occurrence("e1", title: "Caf\u{E9} meeting", day: 1, location: nil, notes: "Agenda"),
            Fixture.occurrence("e1", title: "Caf\u{E9} meeting", location: nil, notes: "Agenda", allDay: true),
            Fixture.shifted(stored, by: 0.001)
        ]
        for (index, data) in incoming.enumerated() {
            let legacy = EventKitMirror.insertEvent(stored, calendarID: "cal", in: context, now: Fixture.firstSync)
            let mirrored = EventKitMirror.insertEvent(stored, calendarID: "cal", in: context, now: Fixture.firstSync)
            Fixture.legacyUpdate(legacy, from: data, now: Fixture.secondSync)
            let changed = EventKitMirror.updateEvent(mirrored, from: data, now: Fixture.secondSync)
            let expectedStamp = changed ? Fixture.secondSync : Fixture.firstSync

            #expect(changed == (index != 0), "case \(index)")
            #expect(EventKitMirror.isSameText(mirrored.title, legacy.title), "case \(index)")
            #expect(EventKitMirror.isSameText(mirrored.location, legacy.location), "case \(index)")
            #expect(EventKitMirror.isSameText(mirrored.notes, legacy.notes), "case \(index)")
            #expect(mirrored.startDate == legacy.startDate, "case \(index)")
            #expect(mirrored.endDate == legacy.endDate, "case \(index)")
            #expect(mirrored.isAllDay == legacy.isAllDay, "case \(index)")
            #expect(mirrored.lastSyncedAt == expectedStamp, "case \(index)")
        }
    }

    @Test("Rows an idle sync rewrites: every returned row with the old copy, none now")
    func idleSyncRowCounts() throws {
        let events = (0..<40).map { Fixture.occurrence("e\($0)", day: $0 % 30) }
        let reminders = (0..<25).map { Fixture.reminder("r\($0)", modified: Fixture.firstSync) }

        let legacyContext = try CoreDataTestHelpers.makeContext()
        Fixture.legacySync(events: events, reminders: reminders, in: legacyContext, now: Fixture.firstSync)
        #expect(legacyContext.safeSave())
        Fixture.legacySync(events: events, reminders: reminders, in: legacyContext, now: Fixture.secondSync)
        #expect(legacyContext.updatedObjects.count == 65)

        let mirrorContext = try CoreDataTestHelpers.makeContext()
        for now in [Fixture.firstSync, Fixture.secondSync] {
            EventKitMirror.reconcileEvents(events, from: Fixture.schoolFetch, in: mirrorContext, now: now)
            EventKitMirror.reconcileReminders(reminders, listID: "list", in: mirrorContext, now: now)
            if now == Fixture.firstSync { #expect(mirrorContext.safeSave()) }
        }
        #expect(mirrorContext.updatedObjects.isEmpty)
        #expect(!mirrorContext.hasChanges)
    }
}
