#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Fetch Tests

@Suite("ReminderRepository Fetch Tests", .serialized)
@MainActor
struct ReminderRepositoryFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Reminder.self,
            Note.self,
        ])
    }

    @Test("fetchReminder returns reminder by ID")
    func fetchReminderReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder = Reminder(title: "Test Reminder")
        context.insert(reminder)
        try context.save()

        let repository = ReminderRepository(context: context)
        let fetched = repository.fetchReminder(id: reminder.id)

        #expect(fetched != nil)
        #expect(fetched?.id == reminder.id)
        #expect(fetched?.title == "Test Reminder")
    }

    @Test("fetchReminder returns nil for missing ID")
    func fetchReminderReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ReminderRepository(context: context)
        let fetched = repository.fetchReminder(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchReminders returns all when no predicate")
    func fetchRemindersReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder1 = Reminder(title: "Reminder 1")
        let reminder2 = Reminder(title: "Reminder 2")
        let reminder3 = Reminder(title: "Reminder 3")
        context.insert(reminder1)
        context.insert(reminder2)
        context.insert(reminder3)
        try context.save()

        let repository = ReminderRepository(context: context)
        let fetched = repository.fetchReminders()

        #expect(fetched.count == 3)
    }

    @Test("fetchReminders sorts by dueDate by default")
    func fetchRemindersSortsByDueDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let earlyDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let lateDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let reminder1 = Reminder(title: "Late Reminder", dueDate: lateDate)
        let reminder2 = Reminder(title: "Early Reminder", dueDate: earlyDate)
        context.insert(reminder1)
        context.insert(reminder2)
        try context.save()

        let repository = ReminderRepository(context: context)
        let fetched = repository.fetchReminders()

        #expect(fetched[0].title == "Early Reminder")
        #expect(fetched[1].title == "Late Reminder")
    }

    @Test("fetchIncompleteReminders returns incomplete only")
    func fetchIncompleteRemindersReturnsIncomplete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder1 = Reminder(title: "Incomplete")
        let reminder2 = Reminder(title: "Complete")
        reminder2.markCompleted()
        context.insert(reminder1)
        context.insert(reminder2)
        try context.save()

        let repository = ReminderRepository(context: context)
        let fetched = repository.fetchIncompleteReminders()

        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Incomplete")
        #expect(fetched[0].isCompleted == false)
    }

    @Test("fetchDueToday returns today and overdue reminders")
    func fetchDueTodayReturnsTodayAndOverdue() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let calendar = Calendar.current
        let today = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let reminder1 = Reminder(title: "Due Today", dueDate: today)
        let reminder2 = Reminder(title: "Overdue", dueDate: yesterday)
        let reminder3 = Reminder(title: "Due Tomorrow", dueDate: tomorrow)
        context.insert(reminder1)
        context.insert(reminder2)
        context.insert(reminder3)
        try context.save()

        let repository = ReminderRepository(context: context)
        let fetched = repository.fetchDueToday(calendar: calendar)

        #expect(fetched.count == 2)
        #expect(fetched.contains { $0.title == "Due Today" })
        #expect(fetched.contains { $0.title == "Overdue" })
        #expect(!fetched.contains { $0.title == "Due Tomorrow" })
    }

    @Test("fetchDueToday excludes completed reminders")
    func fetchDueTodayExcludesCompleted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let today = Date()

        let reminder1 = Reminder(title: "Incomplete", dueDate: today)
        let reminder2 = Reminder(title: "Complete", dueDate: today)
        reminder2.markCompleted()
        context.insert(reminder1)
        context.insert(reminder2)
        try context.save()

        let repository = ReminderRepository(context: context)
        let fetched = repository.fetchDueToday()

        #expect(fetched.count == 1)
        #expect(fetched[0].title == "Incomplete")
    }

    @Test("fetchReminder byEventKitID returns matching reminder")
    func fetchReminderByEventKitID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let eventKitID = "EK12345"
        let reminder = Reminder(title: "Test", eventKitReminderID: eventKitID)
        context.insert(reminder)
        try context.save()

        let repository = ReminderRepository(context: context)
        let fetched = repository.fetchReminder(byEventKitID: eventKitID)

        #expect(fetched != nil)
        #expect(fetched?.eventKitReminderID == eventKitID)
    }

    @Test("fetchReminders handles empty database")
    func fetchRemindersHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ReminderRepository(context: context)
        let fetched = repository.fetchReminders()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Create Tests

@Suite("ReminderRepository Create Tests", .serialized)
@MainActor
struct ReminderRepositoryCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Reminder.self,
            Note.self,
        ])
    }

    @Test("createReminder creates reminder with required fields")
    func createReminderCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ReminderRepository(context: context)
        let reminder = repository.createReminder(title: "Test Reminder")

        #expect(reminder.title == "Test Reminder")
        #expect(reminder.isCompleted == false)
    }

    @Test("createReminder sets optional fields when provided")
    func createReminderSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let dueDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let eventKitID = "EK12345"
        let calendarID = "CAL12345"

        let repository = ReminderRepository(context: context)
        let reminder = repository.createReminder(
            title: "Important Task",
            notes: "Don't forget to complete this",
            dueDate: dueDate,
            eventKitReminderID: eventKitID,
            eventKitCalendarID: calendarID
        )

        #expect(reminder.notes == "Don't forget to complete this")
        #expect(reminder.dueDate == dueDate)
        #expect(reminder.eventKitReminderID == eventKitID)
        #expect(reminder.eventKitCalendarID == calendarID)
    }

    @Test("createReminder persists to context")
    func createReminderPersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ReminderRepository(context: context)
        let reminder = repository.createReminder(title: "Test")

        let fetched = repository.fetchReminder(id: reminder.id)

        #expect(fetched != nil)
        #expect(fetched?.id == reminder.id)
    }
}

// MARK: - Update Tests

@Suite("ReminderRepository Update Tests", .serialized)
@MainActor
struct ReminderRepositoryUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Reminder.self,
            Note.self,
        ])
    }

    @Test("updateReminder updates title")
    func updateReminderUpdatesTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder = Reminder(title: "Original Title")
        context.insert(reminder)
        try context.save()

        let repository = ReminderRepository(context: context)
        let result = repository.updateReminder(id: reminder.id, title: "Updated Title")

        #expect(result == true)
        #expect(reminder.title == "Updated Title")
    }

    @Test("updateReminder updates notes")
    func updateReminderUpdatesNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder = Reminder(title: "Test")
        context.insert(reminder)
        try context.save()

        let repository = ReminderRepository(context: context)
        let result = repository.updateReminder(id: reminder.id, notes: "New notes")

        #expect(result == true)
        #expect(reminder.latestUnifiedNoteText == "New notes")
    }

    @Test("updateReminder clears notes when empty string")
    func updateReminderClearsNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder = Reminder(title: "Test", notes: nil)
        context.insert(reminder)
        _ = reminder.setLegacyNoteText("Old notes", in: context)
        try context.save()

        let repository = ReminderRepository(context: context)
        let result = repository.updateReminder(id: reminder.id, notes: "")

        #expect(result == true)
        #expect(reminder.latestUnifiedNoteText.isEmpty)
    }

    @Test("updateReminder updates dueDate")
    func updateReminderUpdatesDueDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder = Reminder(title: "Test")
        context.insert(reminder)
        try context.save()

        let newDate = TestCalendar.date(year: 2025, month: 3, day: 20)

        let repository = ReminderRepository(context: context)
        let result = repository.updateReminder(id: reminder.id, dueDate: newDate)

        #expect(result == true)
        #expect(reminder.dueDate == newDate)
    }

    @Test("updateReminder updates updatedAt")
    func updateReminderUpdatesUpdatedAt() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder = Reminder(title: "Test")
        let originalUpdatedAt = reminder.updatedAt
        context.insert(reminder)
        try context.save()

        // Small delay to ensure time difference
        try await Task.sleep(for: .milliseconds(10))

        let repository = ReminderRepository(context: context)
        _ = repository.updateReminder(id: reminder.id, title: "Updated")

        #expect(reminder.updatedAt > originalUpdatedAt)
    }

    @Test("updateReminder returns false for missing ID")
    func updateReminderReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ReminderRepository(context: context)
        let result = repository.updateReminder(id: UUID(), title: "New Title")

        #expect(result == false)
    }

    @Test("markCompleted sets isCompleted to true")
    func markCompletedSetsIsCompleted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder = Reminder(title: "Test")
        context.insert(reminder)
        try context.save()

        let repository = ReminderRepository(context: context)
        let result = repository.markCompleted(id: reminder.id)

        #expect(result == true)
        #expect(reminder.isCompleted == true)
    }

    @Test("markCompleted returns false for missing ID")
    func markCompletedReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ReminderRepository(context: context)
        let result = repository.markCompleted(id: UUID())

        #expect(result == false)
    }

    @Test("markIncomplete sets isCompleted to false")
    func markIncompleteSetsIsCompleted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder = Reminder(title: "Test")
        reminder.markCompleted()
        context.insert(reminder)
        try context.save()

        let repository = ReminderRepository(context: context)
        let result = repository.markIncomplete(id: reminder.id)

        #expect(result == true)
        #expect(reminder.isCompleted == false)
    }
}

// MARK: - Delete Tests

@Suite("ReminderRepository Delete Tests", .serialized)
@MainActor
struct ReminderRepositoryDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Reminder.self,
            Note.self,
        ])
    }

    @Test("deleteReminder removes reminder from context")
    func deleteReminderRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reminder = Reminder(title: "Test")
        context.insert(reminder)
        try context.save()

        let reminderID = reminder.id

        let repository = ReminderRepository(context: context)
        try repository.deleteReminder(id: reminderID)

        let fetched = repository.fetchReminder(id: reminderID)
        #expect(fetched == nil)
    }

    @Test("deleteReminder does nothing for missing ID")
    func deleteReminderDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = ReminderRepository(context: context)
        try repository.deleteReminder(id: UUID())

        // Should not throw
    }
}

#endif
