import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the millisecond rule for mirrored dates (Danny, 2026-09-25): CloudKit
/// keeps dates in milliseconds, so a row another device wrote comes back with
/// EventKit's sub-millisecond digits cut off. Dates less than a millisecond
/// apart must not count as a change, or two devices syncing one list would
/// rewrite each other's rows on every sync.
@Suite("EventKit mirrors: dates compared to the millisecond")
@MainActor
struct EventKitMirrorMillisecondTests {

    private typealias Fixture = MirrorFixture

    @Test("Dates under a millisecond apart are the same; a millisecond or more is a change")
    func sameInstantThreshold() {
        let base = Fixture.firstSync
        #expect(EventKitMirror.isSameInstant(nil, nil))
        #expect(!EventKitMirror.isSameInstant(base, nil))
        #expect(!EventKitMirror.isSameInstant(nil, base))
        #expect(EventKitMirror.isSameInstant(base, base))
        #expect(EventKitMirror.isSameInstant(base, base.addingTimeInterval(0.000_4)))
        #expect(EventKitMirror.isSameInstant(base.addingTimeInterval(0.000_9), base))
        #expect(!EventKitMirror.isSameInstant(base, base.addingTimeInterval(0.001)))
        #expect(!EventKitMirror.isSameInstant(base, base.addingTimeInterval(-0.002)))
    }

    @Test("A reminder whose stored dates lost their sub-millisecond digits is not rewritten")
    func truncatedReminderDatesWriteNothing() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let completedAt = Fixture.firstSync.addingTimeInterval(0.123_456_7)
        let modified = Fixture.firstSync.addingTimeInterval(0.987_654_3)
        let reminder = Fixture.reminder("r1", completed: true, completedAt: completedAt, modified: modified)
        EventKitMirror.reconcileReminders([reminder], listID: "list", in: context, now: Fixture.firstSync)
        #expect(context.safeSave())

        // What the row holds after a CloudKit round trip: the same dates, cut to the millisecond.
        let row = try #require(Fixture.reminderRows(in: context)["r1"])
        row.completedAt = Self.millisecondTruncated(completedAt)
        row.updatedAt = Self.millisecondTruncated(modified)
        #expect(context.safeSave())

        let outcome = EventKitMirror.reconcileReminders([reminder], listID: "list", in: context, now: Fixture.secondSync)
        #expect(outcome == EventKitMirror.Outcome())
        #expect(!context.hasChanges)
        #expect(row.lastSyncedAt == Fixture.firstSync)
    }

    @Test("A reminder date that really moved, by a millisecond or more, is copied and stamped")
    func movedReminderDateIsCopied() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let reminder = Fixture.reminder("r1", modified: Fixture.firstSync)
        EventKitMirror.reconcileReminders([reminder], listID: "list", in: context, now: Fixture.firstSync)
        #expect(context.safeSave())

        let moved = Fixture.reminder("r1", modified: Fixture.firstSync.addingTimeInterval(0.002))
        let outcome = EventKitMirror.reconcileReminders([moved], listID: "list", in: context, now: Fixture.secondSync)
        #expect(outcome == EventKitMirror.Outcome(updated: 1))
        let row = try #require(Fixture.reminderRows(in: context)["r1"])
        #expect(row.updatedAt == Fixture.firstSync.addingTimeInterval(0.002))
        #expect(row.lastSyncedAt == Fixture.secondSync)
    }

    @Test("An event whose stored times lost their sub-millisecond digits is not rewritten")
    func truncatedEventTimesWriteNothing() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let precise = Fixture.shifted(Fixture.event("e1"), by: 0.000_7)
        let stored = EventKitMirror.insertEvent(precise, calendarID: "school", in: context, now: Fixture.firstSync)
        stored.startDate = stored.startDate.map(Self.millisecondTruncated)
        stored.endDate = stored.endDate.map(Self.millisecondTruncated)
        #expect(context.safeSave())

        #expect(!EventKitMirror.updateEvent(stored, from: precise, now: Fixture.secondSync))
        #expect(!context.hasChanges)
        #expect(stored.lastSyncedAt == Fixture.firstSync)
    }

    /// A date cut to whole milliseconds, as CloudKit stores it.
    private static func millisecondTruncated(_ date: Date) -> Date {
        let milliseconds = (date.timeIntervalSinceReferenceDate * 1_000).rounded(.down)
        return Date(timeIntervalSinceReferenceDate: milliseconds / 1_000)
    }
}
