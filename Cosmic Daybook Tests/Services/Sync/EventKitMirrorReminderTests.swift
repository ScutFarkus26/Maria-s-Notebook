import Foundation
@preconcurrency import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the reminders mirror's write rule (Danny, 2026-09-25): a sync writes
/// a row, and stamps `lastSyncedAt`, only when the row is new or a value
/// copied from EventKit changed. A reminder EventKit gives no modification
/// date keeps the old rule (`updatedAt` = the sync time), so it is still
/// rewritten on every sync.
@Suite("EventKit mirrors: reminders")
@MainActor
struct EventKitMirrorReminderTests {

    private typealias Fixture = MirrorFixture

    @Test("A second sync over an unchanged list leaves nothing to save and no history")
    func unchangedRemindersWriteNothing() throws {
        let store = try HistoryStoreFixture()
        defer { store.cleanUp() }
        let context = store.stack.viewContext
        let reminders = [
            Fixture.reminder("r1", modified: Fixture.firstSync),
            Fixture.reminder(
                "r2", title: "Call Ms. Levin", notes: "About Friday", due: Fixture.dueSoon, modified: Fixture.firstSync
            ),
            Fixture.reminder(
                "r3", completed: true, completedAt: Fixture.firstSync, created: Fixture.firstSync,
                modified: Fixture.firstSync
            )
        ]

        let first = EventKitMirror.reconcileReminders(reminders, listID: "list", in: context, now: Fixture.firstSync)
        #expect(first == EventKitMirror.Outcome(inserted: 3))
        #expect(context.safeSave())
        let token = try store.historyToken()

        let second = EventKitMirror.reconcileReminders(reminders, listID: "list", in: context, now: Fixture.secondSync)
        #expect(second == EventKitMirror.Outcome())
        #expect(!context.hasChanges)
        #expect(context.safeSave())
        #expect(try store.transactions(after: token).isEmpty)
    }

    @Test("A reminder with no modification date is rewritten every sync, as before; the rest are not")
    func reminderWithoutModificationDateKeepsOldRule() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let modified = Date(timeIntervalSinceReferenceDate: 809_000_000)
        let reminders = [Fixture.reminder("dated", modified: modified), Fixture.reminder("undated", modified: nil)]

        let first = EventKitMirror.reconcileReminders(reminders, listID: "list", in: context, now: Fixture.firstSync)
        #expect(first == EventKitMirror.Outcome(inserted: 2))
        let rows = Fixture.reminderRows(in: context)
        let dated = try #require(rows["dated"])
        let undated = try #require(rows["undated"])
        #expect(dated.updatedAt == modified)
        #expect(undated.updatedAt == Fixture.firstSync)
        #expect(undated.lastSyncedAt == Fixture.firstSync)
        #expect(context.safeSave())

        let second = EventKitMirror.reconcileReminders(reminders, listID: "list", in: context, now: Fixture.secondSync)
        #expect(second == EventKitMirror.Outcome(updated: 1))
        #expect(context.updatedObjects.count == 1)
        #expect(context.updatedObjects.contains(undated))
        #expect(undated.updatedAt == Fixture.secondSync)
        #expect(undated.lastSyncedAt == Fixture.secondSync)
        #expect(dated.lastSyncedAt == Fixture.firstSync)
    }

    @Test("Completing a reminder rewrites only its row, with EventKit's values")
    func completedReminderRewritesOnlyItsRow() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let reminders = [
            Fixture.reminder("r1", modified: Fixture.firstSync),
            Fixture.reminder("r2", due: Fixture.dueSoon, modified: Fixture.firstSync)
        ]
        EventKitMirror.reconcileReminders(reminders, listID: "list", in: context, now: Fixture.firstSync)
        #expect(context.safeSave())

        let completed = Fixture.reminder(
            "r2", due: Fixture.dueSoon, completed: true, completedAt: Fixture.secondSync, modified: Fixture.secondSync
        )
        let outcome = EventKitMirror.reconcileReminders(
            [reminders[0], completed], listID: "list", in: context, now: Fixture.thirdSync
        )
        #expect(outcome == EventKitMirror.Outcome(updated: 1))
        let rows = Fixture.reminderRows(in: context)
        let row = try #require(rows["r2"])
        let untouched = try #require(rows["r1"])
        let dueDate = try #require(Fixture.dueSoon.date)
        #expect(row.isCompleted)
        #expect(row.completedAt == Fixture.secondSync)
        #expect(row.updatedAt == Fixture.secondSync)
        #expect(row.dueDate == dueDate)
        #expect(row.lastSyncedAt == Fixture.thirdSync)
        #expect(untouched.lastSyncedAt == Fixture.firstSync)
    }

    @Test("Each copied field ends exactly as the old copy wrote it")
    func updateMatchesOldCopy() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let stored = Fixture.reminder("r1", title: "Caf\u{E9}", notes: "Milk", modified: Fixture.firstSync)
        let incoming = [
            stored,
            Fixture.reminder("r1", title: "Cafe\u{301}", notes: "Milk", modified: Fixture.firstSync),
            Fixture.reminder("r1", title: "Caf\u{E9}", notes: "", modified: Fixture.firstSync),
            Fixture.reminder(
                "r1", title: "Caf\u{E9}", notes: "Milk", due: Fixture.dueSoon, modified: Fixture.firstSync
            ),
            Fixture.reminder("r1", title: "Caf\u{E9}", notes: "Milk", completed: true, modified: Fixture.firstSync),
            Fixture.reminder("r1", title: "Caf\u{E9}", notes: "Milk", modified: Fixture.secondSync),
            Fixture.reminder("r1", title: "Caf\u{E9}", notes: "Milk", modified: nil)
        ]
        for (index, data) in incoming.enumerated() {
            let legacy = EventKitMirror.insertReminder(stored, listID: "list", in: context, now: Fixture.firstSync)
            let mirrored = EventKitMirror.insertReminder(stored, listID: "list", in: context, now: Fixture.firstSync)
            Fixture.legacyUpdate(legacy, from: data, now: Fixture.thirdSync)
            let changed = EventKitMirror.updateReminder(mirrored, from: data, now: Fixture.thirdSync)
            let expectedStamp = changed ? Fixture.thirdSync : Fixture.firstSync

            #expect(changed == (index != 0), "case \(index)")
            #expect(EventKitMirror.isSameText(mirrored.title, legacy.title), "case \(index)")
            #expect(EventKitMirror.isSameText(mirrored.notes, legacy.notes), "case \(index)")
            #expect(mirrored.dueDate == legacy.dueDate, "case \(index)")
            #expect(mirrored.isCompleted == legacy.isCompleted, "case \(index)")
            #expect(mirrored.completedAt == legacy.completedAt, "case \(index)")
            #expect(mirrored.updatedAt == legacy.updatedAt, "case \(index)")
            #expect(mirrored.createdAt == legacy.createdAt, "case \(index)")
            #expect(mirrored.lastSyncedAt == expectedStamp, "case \(index)")
        }
    }

    @Test("A reminder gone from the list is deleted; another list's rows are kept")
    func reminderDeletionKeepsItsList() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let kept = Fixture.reminder("kept", modified: Fixture.firstSync)
        let gone = Fixture.reminder("gone", modified: Fixture.firstSync)
        let other = Fixture.reminder("other", modified: Fixture.firstSync)
        EventKitMirror.reconcileReminders([kept, gone], listID: "list", in: context, now: Fixture.firstSync)
        EventKitMirror.insertReminder(other, listID: "other-list", in: context, now: Fixture.firstSync)
        #expect(context.safeSave())

        let outcome = EventKitMirror.reconcileReminders([kept], listID: "list", in: context, now: Fixture.secondSync)
        #expect(outcome == EventKitMirror.Outcome(deleted: 1))
        #expect(Set(Fixture.reminderRows(in: context).keys) == ["kept", "other"])
    }
}
