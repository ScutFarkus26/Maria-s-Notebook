// MockEventStore.swift
// Mock implementation for EventKit to test Calendar and Reminder sync services

#if canImport(Testing)
import Foundation
import EventKit
@testable import Maria_s_Notebook

/// Mock calendar/reminder list for testing
struct MockEKCalendar: Identifiable, Hashable {
    let calendarIdentifier: String
    let title: String
    let type: EKEntityType

    var id: String { calendarIdentifier }

    init(identifier: String = UUID().uuidString, title: String, type: EKEntityType) {
        self.calendarIdentifier = identifier
        self.title = title
        self.type = type
    }
}

/// Mock event data for testing
struct MockEKEvent: Identifiable {
    let eventIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?
    let isAllDay: Bool
    let calendarIdentifier: String

    var id: String { eventIdentifier }

    init(
        identifier: String = UUID().uuidString,
        title: String,
        startDate: Date = Date(),
        endDate: Date = Date().addingTimeInterval(3600),
        location: String? = nil,
        notes: String? = nil,
        isAllDay: Bool = false,
        calendarIdentifier: String
    ) {
        self.eventIdentifier = identifier
        self.title = title
        self.startDate = startDate
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.isAllDay = isAllDay
        self.calendarIdentifier = calendarIdentifier
    }
}

/// Mock reminder data for testing
struct MockEKReminder: Identifiable {
    let calendarItemIdentifier: String
    let title: String
    let notes: String?
    let dueDateComponents: DateComponents?
    var isCompleted: Bool
    var completionDate: Date?
    let creationDate: Date?
    let lastModifiedDate: Date?
    let calendarIdentifier: String

    var id: String { calendarItemIdentifier }

    init(
        identifier: String = UUID().uuidString,
        title: String,
        notes: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        completionDate: Date? = nil,
        creationDate: Date? = Date(),
        lastModifiedDate: Date? = Date(),
        calendarIdentifier: String
    ) {
        self.calendarItemIdentifier = identifier
        self.title = title
        self.notes = notes
        if let dueDate = dueDate {
            self.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        } else {
            self.dueDateComponents = nil
        }
        self.isCompleted = isCompleted
        self.completionDate = completionDate
        self.creationDate = creationDate
        self.lastModifiedDate = lastModifiedDate
        self.calendarIdentifier = calendarIdentifier
    }
}

/// Mock event store for testing EventKit interactions
@MainActor
final class MockEventStore {
    /// Simulated authorization status for events
    var eventAuthorizationStatus: EKAuthorizationStatus = .notDetermined

    /// Simulated authorization status for reminders
    var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined

    /// Available calendars
    var calendars: [MockEKCalendar] = []

    /// Events in the store
    var events: [MockEKEvent] = []

    /// Reminders in the store
    var reminders: [MockEKReminder] = []

    /// Whether authorization requests should succeed
    var authorizationShouldSucceed: Bool = true

    /// Error to throw on authorization failure
    var authorizationError: Error?

    /// Tracks whether events/reminders were saved
    private(set) var savedItems: [String] = []

    // MARK: - Setup Helpers

    /// Add a calendar to the mock store
    func addCalendar(_ calendar: MockEKCalendar) {
        calendars.append(calendar)
    }

    /// Add an event to the mock store
    func addEvent(_ event: MockEKEvent) {
        events.append(event)
    }

    /// Add a reminder to the mock store
    func addReminder(_ reminder: MockEKReminder) {
        reminders.append(reminder)
    }

    /// Clear all data
    func reset() {
        calendars.removeAll()
        events.removeAll()
        reminders.removeAll()
        savedItems.removeAll()
        eventAuthorizationStatus = .notDetermined
        reminderAuthorizationStatus = .notDetermined
        authorizationShouldSucceed = true
        authorizationError = nil
    }

    // MARK: - Simulated EventKit API

    /// Simulate requesting full access to events
    func requestFullAccessToEvents() async throws -> Bool {
        if let error = authorizationError {
            throw error
        }
        if authorizationShouldSucceed {
            eventAuthorizationStatus = .fullAccess
            return true
        } else {
            eventAuthorizationStatus = .denied
            return false
        }
    }

    /// Simulate requesting full access to reminders
    func requestFullAccessToReminders() async throws -> Bool {
        if let error = authorizationError {
            throw error
        }
        if authorizationShouldSucceed {
            reminderAuthorizationStatus = .fullAccess
            return true
        } else {
            reminderAuthorizationStatus = .denied
            return false
        }
    }

    /// Get calendars for a specific entity type
    func calendars(for entityType: EKEntityType) -> [MockEKCalendar] {
        calendars.filter { $0.type == entityType }
    }

    /// Find a calendar by identifier
    func calendar(withIdentifier identifier: String) -> MockEKCalendar? {
        calendars.first { $0.calendarIdentifier == identifier }
    }

    /// Get events matching a date range and calendars
    func events(from startDate: Date, to endDate: Date, calendars: [MockEKCalendar]) -> [MockEKEvent] {
        let calendarIDs = Set(calendars.map { $0.calendarIdentifier })
        return events.filter { event in
            calendarIDs.contains(event.calendarIdentifier) &&
            event.startDate >= startDate &&
            event.startDate <= endDate
        }
    }

    /// Get reminders for specific calendars
    func reminders(in calendars: [MockEKCalendar]) -> [MockEKReminder] {
        let calendarIDs = Set(calendars.map { $0.calendarIdentifier })
        return reminders.filter { calendarIDs.contains($0.calendarIdentifier) }
    }

    /// Simulate saving a reminder
    func save(reminder: inout MockEKReminder) {
        savedItems.append(reminder.calendarItemIdentifier)
        // Update in store if exists
        if let index = reminders.firstIndex(where: { $0.calendarItemIdentifier == reminder.calendarItemIdentifier }) {
            reminders[index] = reminder
        }
    }

    /// Check if an item was saved
    func wasSaved(_ identifier: String) -> Bool {
        savedItems.contains(identifier)
    }
}

// MARK: - Test Data Factories

extension MockEKCalendar {
    /// Creates a test calendar for events
    static func testEventCalendar(name: String = "Test Calendar") -> MockEKCalendar {
        MockEKCalendar(title: name, type: .event)
    }

    /// Creates a test reminder list
    static func testReminderList(name: String = "Test Reminders") -> MockEKCalendar {
        MockEKCalendar(title: name, type: .reminder)
    }
}

extension MockEKEvent {
    /// Creates a test event with default values
    static func testEvent(
        title: String = "Test Event",
        calendarIdentifier: String,
        startDate: Date = Date(),
        duration: TimeInterval = 3600
    ) -> MockEKEvent {
        MockEKEvent(
            title: title,
            startDate: startDate,
            endDate: startDate.addingTimeInterval(duration),
            calendarIdentifier: calendarIdentifier
        )
    }

    /// Creates an all-day test event
    static func allDayEvent(
        title: String = "All Day Event",
        calendarIdentifier: String,
        date: Date = Date()
    ) -> MockEKEvent {
        let startOfDay = Calendar.current.startOfDay(for: date)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        return MockEKEvent(
            title: title,
            startDate: startOfDay,
            endDate: endOfDay,
            isAllDay: true,
            calendarIdentifier: calendarIdentifier
        )
    }
}

extension MockEKReminder {
    /// Creates a test reminder with default values
    static func testReminder(
        title: String = "Test Reminder",
        calendarIdentifier: String,
        dueDate: Date? = nil,
        isCompleted: Bool = false
    ) -> MockEKReminder {
        MockEKReminder(
            title: title,
            dueDate: dueDate,
            isCompleted: isCompleted,
            calendarIdentifier: calendarIdentifier
        )
    }

    /// Creates a completed test reminder
    static func completedReminder(
        title: String = "Completed Reminder",
        calendarIdentifier: String
    ) -> MockEKReminder {
        MockEKReminder(
            title: title,
            isCompleted: true,
            completionDate: Date(),
            calendarIdentifier: calendarIdentifier
        )
    }
}
#endif
