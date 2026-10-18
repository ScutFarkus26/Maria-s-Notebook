import Foundation
@preconcurrency import CoreData
import EventKit
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, the EventKit mirrors (#12).
///
/// #12: a sync that found none of the chosen calendars threw before the
/// throttle's time was set, so every Calendar change ran it again, all day.
/// (#13's reminder rekey was backed out after review: see the plan's
/// Open questions.)
@Suite("EventKit mirrors (Fix1017 Cal)")
@MainActor
struct EventKitMirrorsFix1017Cal {

    // MARK: - #12 A missing calendar pauses listening

    @Test("#12 A sync that finds none of the chosen calendars stops listening for changes")
    func missingCalendarPausesListening() async throws {
        let suiteName = "EventKitMirrorsFix1017Cal.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(["gone-\(UUID().uuidString)"], forKey: UserDefaultsKeys.calendarSyncIdentifiers)
        defaults.set(["School Events"], forKey: UserDefaultsKeys.calendarSyncNames)
        let service = CalendarSyncService(context: try CoreDataTestHelpers.makeContext(), defaults: defaults)
        service.authorizationStatus = .fullAccess

        await #expect(throws: CalendarSyncError.self) {
            try await service.syncEvents(force: true)
        }
        #expect(service.isChangeObservationPaused)
        #expect(!service.isObservingChanges)

        // A second failure keeps the pause; a new choice of calendars lifts it.
        service.pauseChangeObservationForMissingCalendars()
        #expect(service.isChangeObservationPaused)
        // No access, so the restart the new choice schedules never reaches EventKit.
        service.authorizationStatus = .denied
        service.updateSelection(identifiers: ["school"], names: ["School"])
        #expect(!service.isChangeObservationPaused)
    }

    @Test("#12 Finding the calendars again resumes a paused calendar sync")
    func calendarResumesWhenFound() throws {
        let suiteName = "EventKitMirrorsFix1017Cal.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let service = CalendarSyncService(context: try CoreDataTestHelpers.makeContext(), defaults: defaults)
        service.authorizationStatus = .denied

        service.pauseChangeObservationForMissingCalendars()
        #expect(service.isChangeObservationPaused)
        service.resumeChangeObservationIfPaused()
        #expect(!service.isChangeObservationPaused)
    }
}
