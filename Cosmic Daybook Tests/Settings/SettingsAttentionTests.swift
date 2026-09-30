import EventKit
import Foundation
import Testing
@testable import CosmicDaybook

/// Pins which "Needs your attention" rows the Overview shows, and where each
/// row's fix button goes.
@Suite("Settings attention")
struct SettingsAttentionTests {

    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func daysAgo(_ days: Int) -> Date {
        AppCalendar.shared.date(byAdding: .day, value: -days, to: now) ?? now
    }

    /// A notebook with nothing to do: backed up yesterday, synced, nothing outside the share.
    private var calm: SettingsAttentionInputs {
        SettingsAttentionInputs(lastBackup: daysAgo(1), syncHealth: .healthy)
    }

    @Test("Nothing to do shows no rows")
    func allSet() {
        #expect(SettingsAttention.items(for: calm, now: now).isEmpty)
    }

    @Test("A backup a week old or older asks for a new one; a newer one doesn't")
    func backupAge() {
        var inputs = calm
        inputs.lastBackup = daysAgo(6)
        #expect(SettingsAttention.items(for: inputs, now: now).isEmpty)

        inputs.lastBackup = daysAgo(7)
        #expect(SettingsAttention.items(for: inputs, now: now) == [.backupDue(daysSinceLastBackup: 7)])

        inputs.lastBackup = daysAgo(30)
        #expect(SettingsAttention.items(for: inputs, now: now) == [.backupDue(daysSinceLastBackup: 30)])
    }

    @Test("Never having backed up asks for a backup")
    func neverBackedUp() {
        var inputs = calm
        inputs.lastBackup = nil
        let items = SettingsAttention.items(for: inputs, now: now)
        #expect(items == [.backupDue(daysSinceLastBackup: nil)])
        #expect(items.first?.destination == nil)
        #expect(items.first?.title == "No backup yet")
    }

    @Test("Only an iCloud error or delay shows a sync row")
    func syncHealth() {
        var inputs = calm
        for quiet in [CloudKitHealthCheck.SyncHealth.healthy, .syncing, .offline, .unknown] {
            inputs.syncHealth = quiet
            #expect(SettingsAttention.items(for: inputs, now: now).isEmpty, "\(quiet) should be quiet")
        }
        inputs.syncHealth = .warning
        #expect(SettingsAttention.items(for: inputs, now: now) == [.syncProblem(isError: false)])
        inputs.syncHealth = .error("Quota exceeded")
        #expect(SettingsAttention.items(for: inputs, now: now) == [.syncProblem(isError: true)])
    }

    @Test("Classroom records outside the share show only when there are some")
    func unsharedRecords() {
        var inputs = calm
        inputs.unsharedClassroomRecords = nil
        #expect(SettingsAttention.items(for: inputs, now: now).isEmpty)
        inputs.unsharedClassroomRecords = 0
        #expect(SettingsAttention.items(for: inputs, now: now).isEmpty)
        inputs.unsharedClassroomRecords = 3
        let items = SettingsAttention.items(for: inputs, now: now)
        #expect(items == [.unsharedClassroomRecords(3)])
        #expect(items.first?.title == "3 classroom records aren't shared")
        #expect(SettingsAttentionItem.unsharedClassroomRecords(1).title == "1 classroom record isn't shared")
    }

    @Test("Carried-over year plans show only when there are some")
    func carriedOver() {
        var inputs = calm
        inputs.carriedOverPlans = 0
        #expect(SettingsAttention.items(for: inputs, now: now).isEmpty)
        inputs.carriedOverPlans = 12
        #expect(SettingsAttention.items(for: inputs, now: now) == [.carriedOverPlans(12)])
        #expect(SettingsAttentionItem.carriedOverPlans(1).title == "1 year-plan target carried over")
    }

    @Test("Lost Calendar or Reminders access is one row naming what's off")
    func connections() {
        var inputs = calm
        inputs.remindersAccessLost = true
        let reminders = SettingsAttention.items(for: inputs, now: now)
        #expect(reminders == [.connectionAccessLost(calendar: false, reminders: true)])
        inputs.calendarAccessLost = true
        let both = SettingsAttention.items(for: inputs, now: now)
        #expect(both == [.connectionAccessLost(calendar: true, reminders: true)])
        #expect(both.first?.title == "Calendar and Reminders access is off")
    }

    @Test("Access counts as lost only for a connection that was set up")
    func accessLost() {
        #expect(SettingsAttention.accessLost(configured: true, status: .denied))
        #expect(SettingsAttention.accessLost(configured: true, status: .restricted))
        #expect(SettingsAttention.accessLost(configured: true, status: .writeOnly))
        #expect(!SettingsAttention.accessLost(configured: true, status: .fullAccess))
        #expect(!SettingsAttention.accessLost(configured: true, status: .notDetermined))
        #expect(!SettingsAttention.accessLost(configured: false, status: .denied))
    }

    @Test("Rows come most urgent first and each opens the right category")
    func orderAndDestinations() {
        let inputs = SettingsAttentionInputs(
            lastBackup: nil,
            syncHealth: .error("Offline"),
            unsharedClassroomRecords: 2,
            carriedOverPlans: 5,
            calendarAccessLost: true
        )
        let items = SettingsAttention.items(for: inputs, now: now)
        #expect(items.map(\.id) == ["sync", "backup", "classroom", "carriedOver", "connections"])
        #expect(items.map(\.destination) == [.syncBackup, nil, .classroom, .schoolYear, .connections])
    }
}
