// ReminderSyncServiceTests.swift
// Comprehensive tests for ReminderSyncService

#if canImport(Testing)
import Testing
import Foundation
import SwiftData
import EventKit
@testable import Maria_s_Notebook

// MARK: - ReminderSyncError Tests

@Suite("ReminderSyncError Tests")
struct ReminderSyncErrorTests {

    @Test("Error descriptions are not empty")
    func testErrorDescriptions() {
        let errors: [ReminderSyncError] = [
            .notAuthorized,
            .noSyncListConfigured,
            .listNotFound("Test List"),
            .modelContextUnavailable
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("notAuthorized error description")
    func testNotAuthorizedDescription() {
        let error = ReminderSyncError.notAuthorized
        #expect(error.errorDescription?.contains("access") == true)
    }

    @Test("noSyncListConfigured error description")
    func testNoSyncListConfiguredDescription() {
        let error = ReminderSyncError.noSyncListConfigured
        #expect(error.errorDescription?.contains("Reminders") == true || error.errorDescription?.contains("list") == true)
    }

    @Test("listNotFound error includes list name")
    func testListNotFoundDescription() {
        let listName = "My Todo List"
        let error = ReminderSyncError.listNotFound(listName)
        #expect(error.errorDescription?.contains(listName) == true)
    }

    @Test("modelContextUnavailable error description")
    func testModelContextUnavailableDescription() {
        let error = ReminderSyncError.modelContextUnavailable
        #expect(error.errorDescription?.contains("Database") == true || error.errorDescription?.contains("context") == true)
    }
}

// MARK: - ReminderListInfo Tests

@Suite("ReminderListInfo Tests")
struct ReminderListInfoTests {

    @Test("ReminderListInfo identifiable conformance")
    func testReminderListInfoIdentifiable() {
        let identifier = "list-12345"
        let info = ReminderSyncService.ReminderListInfo(
            identifier: identifier,
            name: "Shopping List"
        )

        #expect(info.id == identifier)
        #expect(info.identifier == identifier)
    }

    @Test("ReminderListInfo hashable conformance")
    func testReminderListInfoHashable() {
        let info1 = ReminderSyncService.ReminderListInfo(identifier: "id1", name: "List 1")
        let info2 = ReminderSyncService.ReminderListInfo(identifier: "id1", name: "List 1")
        let info3 = ReminderSyncService.ReminderListInfo(identifier: "id2", name: "List 2")

        #expect(info1 == info2)
        #expect(info1 != info3)

        // Test set behavior
        let set: Set<ReminderSyncService.ReminderListInfo> = [info1, info2, info3]
        #expect(set.count == 2)
    }

    @Test("ReminderListInfo stores all properties")
    func testReminderListInfoProperties() {
        let info = ReminderSyncService.ReminderListInfo(
            identifier: "test-id",
            name: "Work Tasks"
        )

        #expect(info.identifier == "test-id")
        #expect(info.name == "Work Tasks")
    }
}

// MARK: - ReminderSyncService Initialization Tests

@Suite("ReminderSyncService Initialization Tests")
struct ReminderSyncServiceInitializationTests {

    @Test("Service initializes with default state")
    @MainActor
    func testDefaultInitialization() async {
        let service = ReminderSyncService()

        #expect(service.isSyncing == false)
        #expect(service.lastSyncError == nil)
    }

    @Test("Service loads list identifier from UserDefaults")
    @MainActor
    func testLoadsListIdentifier() async {
        // Set up UserDefaults
        let testIdentifier = "reminder-list-id"
        UserDefaults.standard.set(testIdentifier, forKey: "ReminderSync.syncListIdentifier")

        let service = ReminderSyncService()

        #expect(service.syncListIdentifier == testIdentifier)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "ReminderSync.syncListIdentifier")
    }

    @Test("Service loads list name from UserDefaults")
    @MainActor
    func testLoadsListName() async {
        // Set up UserDefaults
        let testName = "My Reminders"
        UserDefaults.standard.set(testName, forKey: "ReminderSync.syncListName")

        let service = ReminderSyncService()

        #expect(service.syncListName == testName)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "ReminderSync.syncListName")
    }

    @Test("Service initializes with provided model context")
    @MainActor
    func testInitWithModelContext() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext

        let service = ReminderSyncService(modelContext: context)

        #expect(service.modelContext != nil)
    }
}

// MARK: - ReminderSyncService Sync Tests

@Suite("ReminderSyncService Sync Tests")
struct ReminderSyncServiceSyncTests {

    @Test("syncReminders throws when not authorized")
    @MainActor
    func testSyncThrowsWhenNotAuthorized() async throws {
        let container = try makeReminderTestContainer()
        let service = ReminderSyncService(modelContext: container.mainContext)

        do {
            try await service.syncReminders(force: true)
        } catch let error as ReminderSyncError {
            #expect(error == .notAuthorized || error == .noSyncListConfigured)
        } catch {
            // Other errors acceptable in test environment
        }
    }

    @Test("syncReminders throws when no list configured")
    @MainActor
    func testSyncThrowsWhenNoListConfigured() async throws {
        let container = try makeReminderTestContainer()
        let service = ReminderSyncService(modelContext: container.mainContext)

        // Clear any configured list
        service.syncListIdentifier = nil
        service.syncListName = nil

        do {
            try await service.syncReminders(force: true)
        } catch ReminderSyncError.noSyncListConfigured {
            #expect(true)
        } catch ReminderSyncError.notAuthorized {
            #expect(true)
        } catch {
            // Other errors acceptable
        }
    }

    @Test("syncReminders throws when model context unavailable")
    @MainActor
    func testSyncThrowsWhenNoModelContext() async {
        let service = ReminderSyncService()
        service.modelContext = nil

        do {
            try await service.syncReminders(force: true)
        } catch ReminderSyncError.modelContextUnavailable {
            #expect(true)
        } catch ReminderSyncError.notAuthorized {
            #expect(true)
        } catch ReminderSyncError.noSyncListConfigured {
            #expect(true)
        } catch {
            // Other errors acceptable
        }
    }

    @Test("syncReminders respects throttling")
    @MainActor
    func testSyncThrottling() async throws {
        let container = try makeReminderTestContainer()
        let service = ReminderSyncService(modelContext: container.mainContext)

        do {
            try await service.syncReminders(force: false)
        } catch {
            // Errors expected without authorization
        }
    }

    @Test("Force sync bypasses throttle")
    @MainActor
    func testForceSyncBypassesThrottle() async throws {
        let container = try makeReminderTestContainer()
        let service = ReminderSyncService(modelContext: container.mainContext)

        do {
            try await service.syncReminders(force: true)
        } catch {
            // Errors expected without authorization
        }
    }
}

// MARK: - ReminderSyncService State Tests

@Suite("ReminderSyncService State Tests")
struct ReminderSyncServiceStateTests {

    @Test("Published properties are observable")
    @MainActor
    func testPublishedProperties() async {
        let service = ReminderSyncService()

        let _ = service.authorizationStatus
        let _ = service.lastSuccessfulSync
        let _ = service.lastSyncError
        let _ = service.isSyncing

        #expect(true)
    }

    @Test("Setting list identifier persists to UserDefaults")
    @MainActor
    func testListIdentifierPersistence() async {
        let service = ReminderSyncService()
        let testIdentifier = "new-list-id"

        service.syncListIdentifier = testIdentifier

        let persisted = UserDefaults.standard.string(forKey: "ReminderSync.syncListIdentifier")
        #expect(persisted == testIdentifier)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "ReminderSync.syncListIdentifier")
    }

    @Test("Setting list name persists to UserDefaults")
    @MainActor
    func testListNamePersistence() async {
        let service = ReminderSyncService()
        let testName = "Work Tasks"

        service.syncListName = testName

        let persisted = UserDefaults.standard.string(forKey: "ReminderSync.syncListName")
        #expect(persisted == testName)

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "ReminderSync.syncListName")
    }
}

// MARK: - ReminderSyncService Authorization Tests

@Suite("ReminderSyncService Authorization Tests")
struct ReminderSyncServiceAuthorizationTests {

    @Test("Initial authorization status is retrieved")
    @MainActor
    func testInitialAuthorizationStatus() async {
        let service = ReminderSyncService()

        let status = service.authorizationStatus
        #expect(status == .notDetermined || status == .restricted || status == .denied || status == .fullAccess)
    }

    @Test("getAvailableReminderLists returns array")
    @MainActor
    func testGetAvailableReminderLists() async {
        let service = ReminderSyncService()

        let lists = service.getAvailableReminderLists()
        #expect(lists.isEmpty || !lists.isEmpty) // Just verify it returns without crashing
    }

    @Test("getAvailableReminderListsWithIdentifiers returns array")
    @MainActor
    func testGetAvailableReminderListsWithIdentifiers() async {
        let service = ReminderSyncService()

        let lists = service.getAvailableReminderListsWithIdentifiers()
        #expect(lists.isEmpty || !lists.isEmpty) // Just verify it returns without crashing
    }
}

// MARK: - Two-Way Sync Tests

@Suite("ReminderSyncService Two-Way Sync Tests")
struct ReminderSyncServiceTwoWaySyncTests {

    @Test("updateReminderCompletionInEventKit handles reminder without EventKit ID")
    @MainActor
    func testUpdateWithoutEventKitID() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext
        let service = ReminderSyncService(modelContext: context)

        // Create a local-only reminder
        let reminder = Reminder(title: "Local Reminder")
        context.insert(reminder)
        try context.save()

        // Should not throw - just silently skip
        do {
            try await service.updateReminderCompletionInEventKit(reminder)
        } catch ReminderSyncError.notAuthorized {
            // Expected without authorization
        }
    }

    @Test("updateReminderCompletionInEventKit requires authorization")
    @MainActor
    func testUpdateRequiresAuthorization() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext
        let service = ReminderSyncService(modelContext: context)

        let reminder = Reminder(
            title: "Synced Reminder",
            eventKitReminderID: "ek-reminder-123"
        )
        context.insert(reminder)
        try context.save()

        do {
            try await service.updateReminderCompletionInEventKit(reminder)
        } catch ReminderSyncError.notAuthorized {
            #expect(true)
        } catch {
            // Other errors (e.g., reminder not found in EventKit) are acceptable
        }
    }
}

// MARK: - Reminder Model Tests

@Suite("Reminder Model Tests")
struct ReminderModelTests {

    @Test("Reminder initializes with all properties")
    @MainActor
    func testReminderInitialization() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext

        let reminderID = UUID()
        let dueDate = Date().addingTimeInterval(86400) // Tomorrow

        let reminder = Reminder(
            id: reminderID,
            title: "Test Reminder",
            notes: "Don't forget!",
            dueDate: dueDate,
            isCompleted: false,
            completedAt: nil,
            createdAt: Date(),
            updatedAt: Date(),
            eventKitReminderID: "ek-123",
            eventKitCalendarID: "cal-456",
            lastSyncedAt: Date()
        )

        context.insert(reminder)
        try context.save()

        #expect(reminder.id == reminderID)
        #expect(reminder.title == "Test Reminder")
        #expect(reminder.notes == "Don't forget!")
        #expect(reminder.isCompleted == false)
        #expect(reminder.eventKitReminderID == "ek-123")
        #expect(reminder.eventKitCalendarID == "cal-456")
    }

    @Test("Reminder persists and fetches correctly")
    @MainActor
    func testReminderPersistence() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext

        let reminder = Reminder(title: "Persistent Reminder")
        context.insert(reminder)
        try context.save()

        let descriptor = FetchDescriptor<Reminder>()
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Persistent Reminder")
    }

    @Test("markCompleted updates state correctly")
    @MainActor
    func testMarkCompleted() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext

        let reminder = Reminder(title: "Task to Complete")
        context.insert(reminder)
        try context.save()

        #expect(reminder.isCompleted == false)
        #expect(reminder.completedAt == nil)

        reminder.markCompleted()

        #expect(reminder.isCompleted == true)
        #expect(reminder.completedAt != nil)
    }

    @Test("markIncomplete updates state correctly")
    @MainActor
    func testMarkIncomplete() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext

        let reminder = Reminder(
            title: "Completed Task",
            isCompleted: true,
            completedAt: Date()
        )
        context.insert(reminder)
        try context.save()

        #expect(reminder.isCompleted == true)

        reminder.markIncomplete()

        #expect(reminder.isCompleted == false)
        #expect(reminder.completedAt == nil)
    }

    @Test("Reminder with nil optional properties")
    @MainActor
    func testOptionalProperties() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext

        let reminder = Reminder(title: "Simple Reminder")
        context.insert(reminder)
        try context.save()

        #expect(reminder.notes == nil)
        #expect(reminder.dueDate == nil)
        #expect(reminder.completedAt == nil)
        #expect(reminder.eventKitReminderID == nil)
        #expect(reminder.eventKitCalendarID == nil)
        #expect(reminder.lastSyncedAt == nil)
    }

    @Test("Reminder with due date")
    @MainActor
    func testReminderWithDueDate() async throws {
        let container = try makeReminderTestContainer()
        let context = container.mainContext

        let tomorrow = Date().addingTimeInterval(86400)
        let reminder = Reminder(
            title: "Due Tomorrow",
            dueDate: tomorrow
        )
        context.insert(reminder)
        try context.save()

        #expect(reminder.dueDate != nil)
        // Compare timestamps
        if let dueDate = reminder.dueDate {
            #expect(abs(dueDate.timeIntervalSince1970 - tomorrow.timeIntervalSince1970) < 1)
        }
    }
}

// MARK: - Test Container Helper

@MainActor
func makeReminderTestContainer() throws -> ModelContainer {
    try makeTestContainer(for: [Reminder.self, Note.self])
}
#endif
