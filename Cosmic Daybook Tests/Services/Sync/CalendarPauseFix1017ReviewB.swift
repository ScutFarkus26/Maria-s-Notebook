import Foundation
@preconcurrency import CoreData
import EventKit
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, review (b) #6: #12's pause for missing calendars
/// stopped listening for Calendar changes, so the change that brought the
/// calendars back (after an account refresh hid them for a moment) was
/// missed, and a Mac left on Today stopped syncing events. While paused the
/// service now keeps listening; a change only checks whether a chosen
/// calendar is back, with no sync and no Sync History rows until one is.
@Suite("Calendar pause keeps listening (Fix1017 review b)")
@MainActor
struct CalendarPauseFix1017ReviewB {

    private func makeService(defaults: UserDefaults) throws -> CalendarSyncService {
        defaults.set(["gone-\(UUID().uuidString)"], forKey: UserDefaultsKeys.calendarSyncIdentifiers)
        defaults.set(["School Events"], forKey: UserDefaultsKeys.calendarSyncNames)
        let service = CalendarSyncService(context: try CoreDataTestHelpers.makeContext(), defaults: defaults)
        service.authorizationStatus = .fullAccess
        // Listening, as after a sync that found the calendars.
        service.pauseChangeObservationForMissingCalendars()
        service.resumeChangeObservationIfPaused()
        return service
    }

    @Test("#6 While calendars are missing, changes are still heard but run no sync")
    func pausedKeepsListeningWithoutSyncing() async throws {
        let suiteName = "CalendarPauseFix1017ReviewB.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = try makeService(defaults: defaults)
        #expect(service.isObservingChanges)

        await #expect(throws: CalendarSyncError.self) {
            try await service.syncEvents(force: true)
        }
        #expect(service.isChangeObservationPaused)
        #expect(service.isObservingChanges)

        // A Calendar change while the chosen calendars are still missing.
        service.lastSyncError = nil
        await service.handleEventStoreChanged()
        #expect(service.lastSyncError == nil)
        #expect(!service.isSyncing)
        #expect(service.isChangeObservationPaused)
        #expect(service.isObservingChanges)
    }

    @Test("#6 A change that brings a chosen calendar back lifts the pause and syncs at once")
    func calendarBackResumesAndSyncs() async throws {
        let suiteName = "CalendarPauseFix1017ReviewB.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = try makeService(defaults: defaults)
        let chosen = try #require(service.syncCalendarIdentifiers.first)
        var onDevice = ["someone-else's-calendar"]
        service.calendarIdentifiersOnDevice = { onDevice }

        await #expect(throws: CalendarSyncError.self) {
            try await service.syncEvents(force: true)
        }
        #expect(service.isChangeObservationPaused)
        // A recent sync: the throttle would skip an unforced one.
        service.lastSyncTime = Date()
        service.lastSyncError = nil

        await service.handleEventStoreChanged()
        #expect(service.isChangeObservationPaused)
        #expect(service.lastSyncError == nil)

        onDevice.append(chosen)
        await service.handleEventStoreChanged()
        // A sync ran past the throttle. The test's Calendar has no such
        // calendar for it to read, so that sync fails and pauses again.
        #expect(service.lastSyncError != nil)
        #expect(service.isObservingChanges)
    }
}
