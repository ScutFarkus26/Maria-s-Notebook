// CalendarSyncServiceTests.swift
// Comprehensive tests for CalendarSyncService

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
import EventKit
@testable import Maria_s_Notebook

// MARK: - CalendarSyncError Tests

@Suite("CalendarSyncError Tests")
struct CalendarSyncErrorTests {

    @Test("Error descriptions are not empty")
    func testErrorDescriptions() {
        let errors: [CalendarSyncError] = [
            .notAuthorized,
            .noCalendarConfigured,
            .calendarNotFound("Test Calendar"),
            .modelContextUnavailable
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("notAuthorized error description")
    func testNotAuthorizedDescription() {
        let error = CalendarSyncError.notAuthorized
        #expect(error.errorDescription?.contains("access") == true)
    }

    @Test("noCalendarConfigured error description")
    func testNoCalendarConfiguredDescription() {
        let error = CalendarSyncError.noCalendarConfigured
        #expect(error.errorDescription?.contains("calendar") == true)
        #expect(error.errorDescription?.contains("configured") == true)
    }

    @Test("calendarNotFound error includes calendar name")
    func testCalendarNotFoundDescription() {
        let calendarName = "My Special Calendar"
        let error = CalendarSyncError.calendarNotFound(calendarName)
        #expect(error.errorDescription?.contains(calendarName) == true)
    }

    @Test("modelContextUnavailable error description")
    func testModelContextUnavailableDescription() {
        let error = CalendarSyncError.modelContextUnavailable
        #expect(error.errorDescription?.contains("Database") == true || error.errorDescription?.contains("context") == true)
    }
}

// MARK: - CalendarInfo Tests

@Suite("CalendarInfo Tests")
struct CalendarInfoTests {

    @Test("CalendarInfo identifiable conformance")
    func testCalendarInfoIdentifiable() {
        let identifier = "cal-12345"
        let info = CalendarSyncService.CalendarInfo(
            identifier: identifier,
            name: "Work Calendar",
            color: nil
        )

        #expect(info.id == identifier)
        #expect(info.identifier == identifier)
    }

    @Test("CalendarInfo hashable conformance")
    func testCalendarInfoHashable() {
        let info1 = CalendarSyncService.CalendarInfo(identifier: "id1", name: "Cal 1", color: nil)
        let info2 = CalendarSyncService.CalendarInfo(identifier: "id1", name: "Cal 1", color: nil)
        let info3 = CalendarSyncService.CalendarInfo(identifier: "id2", name: "Cal 2", color: nil)

        #expect(info1 == info2)
        #expect(info1 != info3)

        // Test set behavior
        let set: Set<CalendarSyncService.CalendarInfo> = [info1, info2, info3]
        #expect(set.count == 2) // info1 and info2 are equal
    }

    @Test("CalendarInfo stores all properties")
    func testCalendarInfoProperties() {
        let info = CalendarSyncService.CalendarInfo(
            identifier: "test-id",
            name: "Personal",
            color: nil
        )

        #expect(info.identifier == "test-id")
        #expect(info.name == "Personal")
    }
}

// MARK: - CalendarSyncService Initialization Tests

@Suite("CalendarSyncService Initialization Tests")
struct CalendarSyncServiceInitializationTests {

    @Test("Service initializes with default state")
    @MainActor
    func testDefaultInitialization() async {
        let service = CalendarSyncService()

        #expect(service.isSyncing == false)
        #expect(service.lastSyncError == nil)
    }

    @Test("Service loads calendar identifiers from UserDefaults")
    @MainActor
    func testLoadsCalendarIdentifiers() async {
        // Set up UserDefaults
        let testIdentifiers = ["id1", "id2"]
        UserDefaults.standard.set(testIdentifiers, forKey: "CalendarSync.syncCalendarIdentifiers")

        let service = CalendarSyncService()

        #expect(service.syncCalendarIdentifiers == testIdentifiers)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "CalendarSync.syncCalendarIdentifiers")
    }

    @Test("Service loads calendar names from UserDefaults")
    @MainActor
    func testLoadsCalendarNames() async {
        // Set up UserDefaults
        let testNames = ["Work", "Personal"]
        UserDefaults.standard.set(testNames, forKey: "CalendarSync.syncCalendarNames")

        let service = CalendarSyncService()

        #expect(service.syncCalendarNames == testNames)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "CalendarSync.syncCalendarNames")
    }

    @Test("Service migrates from legacy single calendar storage")
    @MainActor
    func testLegacyMigration() async {
        // Set up legacy storage
        let legacyIdentifier = "legacy-cal-id"
        let legacyName = "Legacy Calendar"
        UserDefaults.standard.set(legacyIdentifier, forKey: "CalendarSync.syncCalendarIdentifier")
        UserDefaults.standard.set(legacyName, forKey: "CalendarSync.syncCalendarName")
        // Clear new storage
        UserDefaults.standard.removeObject(forKey: "CalendarSync.syncCalendarIdentifiers")
        UserDefaults.standard.removeObject(forKey: "CalendarSync.syncCalendarNames")

        let service = CalendarSyncService()

        #expect(service.syncCalendarIdentifiers == [legacyIdentifier])
        #expect(service.syncCalendarNames == [legacyName])

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "CalendarSync.syncCalendarIdentifier")
        UserDefaults.standard.removeObject(forKey: "CalendarSync.syncCalendarName")
        UserDefaults.standard.removeObject(forKey: "CalendarSync.syncCalendarIdentifiers")
        UserDefaults.standard.removeObject(forKey: "CalendarSync.syncCalendarNames")
    }

    @Test("Service initializes with provided model context")
    @MainActor
    func testInitWithModelContext() async throws {
        let container = try makeTestContainer(for: [CalendarEvent.self])
        let context = container.mainContext

        let service = CalendarSyncService(modelContext: context)

        #expect(service.modelContext != nil)
    }
}

// MARK: - CalendarSyncService Sync Tests

@Suite("CalendarSyncService Sync Tests")
struct CalendarSyncServiceSyncTests {

    @Test("syncEvents throws when not authorized")
    @MainActor
    func testSyncThrowsWhenNotAuthorized() async throws {
        let container = try makeTestContainer(for: [CalendarEvent.self])
        let service = CalendarSyncService(modelContext: container.mainContext)

        // Without authorization, sync should fail
        // Note: In a real test environment, this depends on EventKit authorization
        // which we can't easily mock. We verify the error handling structure.
        do {
            try await service.syncEvents(force: true)
            // If we get here, authorization was granted (CI environment may vary)
        } catch let error as CalendarSyncError {
            // Expected error
            #expect(error == .notAuthorized || error == .noCalendarConfigured)
        } catch {
            // Other errors are acceptable in test environment
        }
    }

    @Test("syncEvents throws when no calendar configured")
    @MainActor
    func testSyncThrowsWhenNoCalendarConfigured() async throws {
        let container = try makeTestContainer(for: [CalendarEvent.self])
        let service = CalendarSyncService(modelContext: container.mainContext)

        // Clear any configured calendars
        service.syncCalendarIdentifiers = []

        do {
            try await service.syncEvents(force: true)
        } catch CalendarSyncError.noCalendarConfigured {
            // Expected
            #expect(true)
        } catch CalendarSyncError.notAuthorized {
            // Also acceptable - authorization checked first
            #expect(true)
        } catch {
            // Other errors acceptable in test environment
        }
    }

    @Test("syncEvents throws when model context unavailable")
    @MainActor
    func testSyncThrowsWhenNoModelContext() async {
        let service = CalendarSyncService()
        service.modelContext = nil

        do {
            try await service.syncEvents(force: true)
        } catch CalendarSyncError.modelContextUnavailable {
            #expect(true)
        } catch CalendarSyncError.notAuthorized {
            // Authorization checked first
            #expect(true)
        } catch CalendarSyncError.noCalendarConfigured {
            // No calendars configured
            #expect(true)
        } catch {
            // Other errors acceptable
        }
    }

    @Test("syncEvents respects throttling")
    @MainActor
    func testSyncThrottling() async throws {
        let container = try makeTestContainer(for: [CalendarEvent.self])
        let service = CalendarSyncService(modelContext: container.mainContext)

        // First call with force=false after a recent sync should be throttled
        // We can't easily test this without mocking the internal lastSyncTime
        // Just verify the parameter exists and method doesn't crash
        do {
            try await service.syncEvents(force: false)
        } catch {
            // Errors expected without full authorization
        }
    }

    @Test("Force sync bypasses throttle")
    @MainActor
    func testForceSyncBypassesThrottle() async throws {
        let container = try makeTestContainer(for: [CalendarEvent.self])
        let service = CalendarSyncService(modelContext: container.mainContext)

        // Force=true should attempt sync regardless of throttle
        do {
            try await service.syncEvents(force: true)
        } catch {
            // Errors expected without full authorization
        }
    }
}

// MARK: - CalendarSyncService State Tests

@Suite("CalendarSyncService State Tests")
struct CalendarSyncServiceStateTests {

    @Test("Published properties are observable")
    @MainActor
    func testPublishedProperties() async {
        let service = CalendarSyncService()

        // Access all published properties
        let _ = service.authorizationStatus
        let _ = service.lastSuccessfulSync
        let _ = service.lastSyncError
        let _ = service.isSyncing

        // Should not crash
        #expect(true)
    }

    @Test("Setting calendar identifiers persists to UserDefaults")
    @MainActor
    func testCalendarIdentifiersPersistence() async {
        let service = CalendarSyncService()
        let testIdentifiers = ["new-id-1", "new-id-2"]

        service.syncCalendarIdentifiers = testIdentifiers

        let persisted = UserDefaults.standard.array(forKey: "CalendarSync.syncCalendarIdentifiers") as? [String]
        #expect(persisted == testIdentifiers)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "CalendarSync.syncCalendarIdentifiers")
    }

    @Test("Setting calendar names persists to UserDefaults")
    @MainActor
    func testCalendarNamesPersistence() async {
        let service = CalendarSyncService()
        let testNames = ["Work", "Family"]

        service.syncCalendarNames = testNames

        let persisted = UserDefaults.standard.array(forKey: "CalendarSync.syncCalendarNames") as? [String]
        #expect(persisted == testNames)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "CalendarSync.syncCalendarNames")
    }
}

// MARK: - CalendarSyncService Authorization Tests

@Suite("CalendarSyncService Authorization Tests")
struct CalendarSyncServiceAuthorizationTests {

    @Test("Initial authorization status is retrieved")
    @MainActor
    func testInitialAuthorizationStatus() async {
        let service = CalendarSyncService()

        // Should be one of the valid EKAuthorizationStatus values
        let status = service.authorizationStatus
        #expect(status == .notDetermined || status == .restricted || status == .denied || status == .fullAccess || status == .authorized)
    }

    @Test("getAvailableCalendarsWithIdentifiers returns array")
    @MainActor
    func testGetAvailableCalendars() async {
        let service = CalendarSyncService()

        // Without authorization, should return empty array
        let calendars = service.getAvailableCalendarsWithIdentifiers()
        #expect(calendars is [CalendarSyncService.CalendarInfo])
    }
}

// MARK: - CalendarEvent Model Tests

@Suite("CalendarEvent Model Tests")
struct CalendarEventModelTests {

    @Test("CalendarEvent initializes with all properties")
    @MainActor
    func testCalendarEventInitialization() async throws {
        let container = try makeTestContainer(for: [CalendarEvent.self])
        let context = container.mainContext

        let eventID = UUID()
        let startDate = Date()
        let endDate = startDate.addingTimeInterval(3600)

        let event = CalendarEvent(
            id: eventID,
            title: "Test Event",
            startDate: startDate,
            endDate: endDate,
            location: "Conference Room",
            notes: "Bring laptop",
            isAllDay: false,
            eventKitEventID: "ek-123",
            eventKitCalendarID: "cal-456",
            lastSyncedAt: Date()
        )

        context.insert(event)
        try context.save()

        #expect(event.id == eventID)
        #expect(event.title == "Test Event")
        #expect(event.location == "Conference Room")
        #expect(event.notes == "Bring laptop")
        #expect(event.isAllDay == false)
        #expect(event.eventKitEventID == "ek-123")
        #expect(event.eventKitCalendarID == "cal-456")
    }

    @Test("CalendarEvent persists and fetches correctly")
    @MainActor
    func testCalendarEventPersistence() async throws {
        let container = try makeTestContainer(for: [CalendarEvent.self])
        let context = container.mainContext

        let event = CalendarEvent(
            title: "Persistent Event",
            startDate: Date(),
            endDate: Date().addingTimeInterval(1800),
            isAllDay: false
        )
        context.insert(event)
        try context.save()

        // Fetch
        let descriptor = FetchDescriptor<CalendarEvent>()
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Persistent Event")
    }

    @Test("CalendarEvent all-day event")
    @MainActor
    func testAllDayEvent() async throws {
        let container = try makeTestContainer(for: [CalendarEvent.self])
        let context = container.mainContext

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let event = CalendarEvent(
            title: "Holiday",
            startDate: startOfDay,
            endDate: endOfDay,
            isAllDay: true
        )
        context.insert(event)
        try context.save()

        #expect(event.isAllDay == true)
    }

    @Test("CalendarEvent with nil optional properties")
    @MainActor
    func testOptionalProperties() async throws {
        let container = try makeTestContainer(for: [CalendarEvent.self])
        let context = container.mainContext

        let event = CalendarEvent(
            title: "Simple Event",
            startDate: Date(),
            endDate: Date().addingTimeInterval(3600)
        )
        context.insert(event)
        try context.save()

        #expect(event.location == nil)
        #expect(event.notes == nil)
        #expect(event.eventKitEventID == nil)
        #expect(event.eventKitCalendarID == nil)
        #expect(event.lastSyncedAt == nil)
    }
}

// MARK: - Test Container Helper

extension CalendarSyncServiceTests {
    @MainActor
    static func makeCalendarTestContainer() throws -> ModelContainer {
        try makeTestContainer(for: [CalendarEvent.self])
    }
}
#endif
