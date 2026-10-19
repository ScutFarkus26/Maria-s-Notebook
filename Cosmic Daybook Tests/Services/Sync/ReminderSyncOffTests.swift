import Foundation
@preconcurrency import CoreData
import EventKit
import Testing
@testable import CosmicDaybook

/// Settings › Reminders › "Show reminders from: Off" (Simplify the app,
/// Phase 9): on this device only, it stops listening for Reminders changes
/// and lets go of the event store. The rows already in the notebook, and
/// their links, stay: they're in iCloud with every other device's.
@Suite("Reminders sync turned off")
@MainActor
struct ReminderSyncOffTests {

    private typealias Fixture = MirrorFixture

    /// UserDefaults of the test's own, so the service never reads or writes
    /// the app's Reminders setting.
    private let suiteName = "ReminderSyncOffTests.\(UUID().uuidString)"
    private let defaults: UserDefaults
    private let context: NSManagedObjectContext

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
        context = try CoreDataTestHelpers.makeContext()
    }

    private func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    /// A service with this device's list chosen, as a device with sync on has it.
    private func serviceSyncingList(access: EKAuthorizationStatus) -> ReminderSyncService {
        defaults.set("list", forKey: UserDefaultsKeys.reminderSyncListIdentifier)
        defaults.set("Class Reminders", forKey: UserDefaultsKeys.reminderSyncListName)
        let service = ReminderSyncService(context: context, defaults: defaults)
        service.authorizationStatus = access
        return service
    }

    /// Every reminder row's id, link, list and title.
    private func snapshot() -> [String] {
        context.safeFetch(CDFetchRequest(CDReminder.self))
            .map { row in
                [row.id?.uuidString, row.eventKitReminderID, row.eventKitCalendarID, row.title]
                    .map { $0 ?? "-" }.joined(separator: "|")
            }
            .sorted()
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(30)
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    @Test("Turning sync off leaves every row and link in place, stops listening and lets go of the store")
    func offLeavesEveryRow() async throws {
        defer { cleanUp() }
        // This device's rows, another device's, and a restored copy with no link.
        let reminders = [
            UnlinkedReminderFixture.reminder("r1", modified: Fixture.firstSync),
            UnlinkedReminderFixture.reminder("r2", title: "Call Ms. Levin", due: Fixture.dueSoon, modified: Fixture.firstSync)
        ]
        EventKitMirror.reconcileReminders(reminders, listID: "list", in: context, now: Fixture.firstSync)
        EventKitMirror.insertReminder(
            UnlinkedReminderFixture.reminder("ipad-r1", modified: Fixture.firstSync), listID: "ipad-list", in: context,
            now: Fixture.firstSync
        )
        CDReminder(context: context).title = "Field trip forms"
        #expect(context.safeSave())
        let before = snapshot()
        #expect(before.count == 4)

        let service = serviceSyncingList(access: .fullAccess)
        // A list choice starts listening, which makes the event store.
        service.syncListIdentifier = "list"
        #expect(await waitUntil { service.isObservingChanges })
        #expect(service.isHoldingEventStore)

        service.turnOff()
        #expect(!service.isObservingChanges)
        #expect(!service.isHoldingEventStore)
        #expect(!service.isListConfigured)
        #expect(defaults.string(forKey: UserDefaultsKeys.reminderSyncListIdentifier) == nil)
        #expect(defaults.string(forKey: UserDefaultsKeys.reminderSyncListName) == nil)

        // The setting change's own follow-up doesn't start listening again.
        try await Task.sleep(for: .milliseconds(100))
        #expect(!service.isObservingChanges)
        #expect(!service.isHoldingEventStore)

        // A sync now has no list to read and writes nothing.
        await #expect(throws: ReminderSyncError.noSyncListConfigured) {
            try await service.syncReminders(force: true)
        }
        #expect(!service.isHoldingEventStore)
        #expect(!context.hasChanges)
        #expect(snapshot() == before)

        // An answer EventKit gives after Off (here: the list now empty, which
        // would delete this device's rows) is dropped: rows and links stay.
        #expect(!service.applyFetchedReminders([], fromList: "list", in: context))
        #expect(!context.hasChanges)
        #expect(snapshot() == before)
    }

    @Test("A sync that EventKit answers after Off, or after another list is picked, writes nothing")
    func lateSyncWritesNothing() throws {
        defer { cleanUp() }
        let service = serviceSyncingList(access: .denied)
        let first = UnlinkedReminderFixture.reminder("r1", modified: Fixture.firstSync)
        let second = UnlinkedReminderFixture.reminder("r2", title: "Call Ms. Levin", modified: Fixture.firstSync)

        // Still on the list it fetched: written.
        #expect(service.applyFetchedReminders([first], fromList: "list", in: context))
        #expect(snapshot().count == 1)

        service.syncListIdentifier = "new-list"
        #expect(!service.applyFetchedReminders([first, second], fromList: "list", in: context))
        service.turnOff()
        #expect(!service.applyFetchedReminders([first, second], fromList: "list", in: context))
        #expect(!context.hasChanges)
        #expect(snapshot().count == 1)
    }

    @Test("With sync off, ticking a reminder leaves Reminders alone")
    func offSkipsWriteBack() async throws {
        defer { cleanUp() }
        let service = serviceSyncingList(access: .denied)
        let row = EventKitMirror.insertReminder(
            UnlinkedReminderFixture.reminder("r1", modified: Fixture.firstSync), listID: "list", in: context, now: Fixture.firstSync
        )

        // On, it goes on to Reminders (refused here: no access).
        await #expect(throws: ReminderSyncError.notAuthorized) {
            try await service.updateReminderCompletionInEventKit(row)
        }

        service.turnOff()
        row.markCompleted()
        try await service.updateReminderCompletionInEventKit(row)
        #expect(!service.isHoldingEventStore)
        #expect(row.eventKitReminderID == "r1")
    }

    @Test("The list choice is this device's own: neither synced through iCloud nor carried by backups")
    func choiceIsPerDevice() {
        for key in [UserDefaultsKeys.reminderSyncListIdentifier, UserDefaultsKeys.reminderSyncListName] {
            #expect(!SyncedPreferencesStore.syncedKeys.contains(key))
            #expect(!SyncedPreferencesStore.syncedKeyPrefixes.contains { key.hasPrefix($0) })
            #expect(!BackupPreferencesService.isBackedUp(key))
        }
    }
}
