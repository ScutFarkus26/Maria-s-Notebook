import EventKit
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - Calendar and Reminders sync, in plain English
//
// Today's header shows the services' `lastSyncError` as its tooltip, and the
// sync settings pass the same errors through `AppErrorMessages.syncMessage`.
// Both read the errors' own descriptions, so those say what happened and what
// to do; the raw text goes to the log and Sync History's Details.

@Suite("Calendar and Reminders sync: plain-English errors", .serialized)
@MainActor
struct CalendarSyncMessageTests {

    private static let developerWords = [
        "Please", "has not been granted", "Database context", "configured", "'School'", "'Classroom'"
    ]

    private var errors: [any LocalizedError] {
        [
            CalendarSyncError.notAuthorized, CalendarSyncError.noCalendarConfigured,
            CalendarSyncError.calendarNotFound("School"), CalendarSyncError.calendarNotFound(""),
            CalendarSyncError.modelContextUnavailable,
            ReminderSyncError.notAuthorized, ReminderSyncError.noSyncListConfigured,
            ReminderSyncError.listNotFound("Classroom"), ReminderSyncError.listNotFound(""),
            ReminderSyncError.modelContextUnavailable
        ]
    }

    @Test("No error uses developer wording or leaves an empty name in quotes")
    func errorsArePlain() {
        for error in errors {
            let message = error.errorDescription ?? ""
            #expect(!message.isEmpty)
            for word in Self.developerWords {
                #expect(!message.contains(word), "\"\(message)\" contains \(word)")
            }
            #expect(!message.contains("\u{201C}\u{201D}"))
        }
    }

    @Test("Access being off names the Privacy & Security pane to turn it on in")
    func accessOff() {
        #expect(CalendarSyncError.notAuthorized.errorDescription
            == "Cosmic Daybook doesn't have access to Calendar. "
            + "Turn it on in \(SystemSettingsApp.privacyPath("Calendars")).")
        #expect(ReminderSyncError.notAuthorized.errorDescription
            == "Cosmic Daybook doesn't have access to Reminders. "
            + "Turn it on in \(SystemSettingsApp.privacyPath("Reminders")).")
    }

    @Test("A failed sync keeps the plain sentence for Today's header and logs the raw text as the detail")
    func failedSyncStoresPlainMessage() async throws {
        let suiteName = "calendar-sync-plain-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let calendar = CalendarSyncService(context: nil, defaults: defaults)
        calendar.authorizationStatus = .denied
        await #expect(throws: CalendarSyncError.notAuthorized) { try await calendar.syncEvents(force: true) }
        #expect(calendar.lastSyncError == CalendarSyncError.notAuthorized.errorDescription)
        // Other suites log to the shared history too, so look for this row rather than the newest.
        #expect(SyncEventLogger.shared.events.contains { row in
            row.type == "calendar" && row.shownMessage == "Couldn't sync with Calendar"
                && row.shownDetail?.contains("CalendarSyncError") == true
        })

        let reminders = ReminderSyncService(context: nil, defaults: defaults)
        reminders.authorizationStatus = .denied
        await #expect(throws: ReminderSyncError.notAuthorized) { try await reminders.syncReminders(force: true) }
        #expect(reminders.lastSyncError == ReminderSyncError.notAuthorized.errorDescription)
    }
}
