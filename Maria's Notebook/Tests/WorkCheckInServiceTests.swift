#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - WorkCheckInService Creation Tests

@Suite("WorkCheckInService Creation Tests", .serialized)
@MainActor
struct WorkCheckInServiceCreationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("createCheckIn creates check-in linked to work")
    func createCheckInCreatesLinkedCheckIn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let service = WorkCheckInService(context: context)
        let date = TestCalendar.date(year: 2025, month: 3, day: 15)

        let checkIn = try service.createCheckIn(for: work, date: date, purpose: "Review progress")

        #expect(checkIn.work?.id == work.id)
        #expect(checkIn.purpose == "Review progress")
        #expect(checkIn.status == .scheduled)
    }

    @Test("createCheckIn adds check-in to work's checkIns array")
    func createCheckInAddsToWorkArray() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let service = WorkCheckInService(context: context)
        let date = TestCalendar.date(year: 2025, month: 3, day: 15)

        _ = try service.createCheckIn(for: work, date: date)

        #expect(work.checkIns?.count == 1)
    }

    @Test("createCheckIn trims whitespace from purpose")
    func createCheckInTrimsPurpose() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date(), purpose: "  Review  ")

        #expect(checkIn.purpose == "Review")
    }

    @Test("createCheckIn trims whitespace from note")
    func createCheckInTrimsNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date(), note: "  Important  ")

        #expect(checkIn.note == "Important")
    }

    @Test("createCheckIn can create with custom status")
    func createCheckInWithCustomStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date(), status: .completed)

        #expect(checkIn.status == .completed)
    }

    @Test("createCheckIn can create multiple check-ins")
    func createCheckInCreatesMultiple() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let service = WorkCheckInService(context: context)

        _ = try service.createCheckIn(for: work, date: Date(), purpose: "First")
        _ = try service.createCheckIn(for: work, date: Date(), purpose: "Second")
        _ = try service.createCheckIn(for: work, date: Date(), purpose: "Third")

        #expect(work.checkIns?.count == 3)
    }
}

// MARK: - WorkCheckInService Update Tests

@Suite("WorkCheckInService Update Tests", .serialized)
@MainActor
struct WorkCheckInServiceUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("markCompleted changes status to completed")
    func markCompletedChangesStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())

        #expect(checkIn.status == .scheduled)

        try service.markCompleted(checkIn)

        #expect(checkIn.status == .completed)
    }

    @Test("markCompleted updates note if provided")
    func markCompletedUpdatesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())

        try service.markCompleted(checkIn, note: "Good progress")

        #expect(checkIn.note == "Good progress")
    }

    @Test("reschedule changes date and keeps scheduled status")
    func rescheduleChangesDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let originalDate = TestCalendar.date(year: 2025, month: 3, day: 10)
        let newDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let checkIn = try service.createCheckIn(for: work, date: originalDate)
        try service.reschedule(checkIn, to: newDate)

        let components = Calendar.current.dateComponents([.day], from: checkIn.date)
        #expect(components.day == 15)
        #expect(checkIn.status == .scheduled)
    }

    @Test("reschedule updates note if provided")
    func rescheduleUpdatesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())

        try service.reschedule(checkIn, to: Date(), note: "Moved to next week")

        #expect(checkIn.note == "Moved to next week")
    }

    @Test("skip changes status to skipped")
    func skipChangesStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())

        try service.skip(checkIn)

        #expect(checkIn.status == .skipped)
    }

    @Test("skip updates note if provided")
    func skipUpdatesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())

        try service.skip(checkIn, note: "Student absent")

        #expect(checkIn.note == "Student absent")
    }

    @Test("updateNote sets note value")
    func updateNoteSetsValue() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())

        try service.updateNote(checkIn, to: "New note")

        #expect(checkIn.note == "New note")
    }

    @Test("updateNote trims whitespace")
    func updateNoteTrimsWhitespace() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())

        try service.updateNote(checkIn, to: "  Trimmed note  ")

        #expect(checkIn.note == "Trimmed note")
    }

    @Test("updateNote handles nil")
    func updateNoteHandlesNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date(), note: "Original")

        try service.updateNote(checkIn, to: nil)

        #expect(checkIn.note == "")
    }

    @Test("update changes all fields")
    func updateChangesAllFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let originalDate = TestCalendar.date(year: 2025, month: 3, day: 10)
        let checkIn = try service.createCheckIn(for: work, date: originalDate, purpose: "Original", note: "Original note")

        let newDate = TestCalendar.date(year: 2025, month: 3, day: 20)
        try service.update(checkIn, date: newDate, status: .completed, purpose: "Updated", note: "Updated note")

        #expect(checkIn.status == .completed)
        #expect(checkIn.purpose == "Updated")
        #expect(checkIn.note == "Updated note")
    }

    @Test("update trims purpose and note")
    func updateTrimsFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())

        try service.update(checkIn, date: Date(), status: .completed, purpose: "  Trimmed  ", note: "  Also trimmed  ")

        #expect(checkIn.purpose == "Trimmed")
        #expect(checkIn.note == "Also trimmed")
    }
}

// MARK: - WorkCheckInService Deletion Tests

@Suite("WorkCheckInService Deletion Tests", .serialized)
@MainActor
struct WorkCheckInServiceDeletionTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("delete removes check-in from context")
    func deleteRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())
        let checkInID = checkIn.id

        try context.save()

        try service.delete(checkIn, from: work)
        try context.save()

        let descriptor = FetchDescriptor<WorkCheckIn>(predicate: #Predicate { $0.id == checkInID })
        let fetched = try context.fetch(descriptor)

        #expect(fetched.isEmpty)
    }

    @Test("delete removes check-in from work's checkIns array")
    func deleteRemovesFromWorkArray() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())

        #expect(work.checkIns?.count == 1)

        try service.delete(checkIn, from: work)

        #expect(work.checkIns?.isEmpty == true)
    }

    @Test("delete without work reference still removes from context")
    func deleteWithoutWorkReference() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)

        let service = WorkCheckInService(context: context)
        let checkIn = try service.createCheckIn(for: work, date: Date())
        let checkInID = checkIn.id

        try context.save()

        try service.delete(checkIn)
        try context.save()

        let descriptor = FetchDescriptor<WorkCheckIn>(predicate: #Predicate { $0.id == checkInID })
        let fetched = try context.fetch(descriptor)

        #expect(fetched.isEmpty)
    }
}

// MARK: - WorkCheckInService Integration Tests

@Suite("WorkCheckInService Integration Tests", .serialized)
@MainActor
struct WorkCheckInServiceIntegrationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("Full lifecycle: create, update, complete, delete")
    func fullLifecycle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let service = WorkCheckInService(context: context)

        // Create
        let checkIn = try service.createCheckIn(for: work, date: Date(), purpose: "Initial review")
        #expect(checkIn.status == .scheduled)
        #expect(work.checkIns?.count == 1)

        // Update note
        try service.updateNote(checkIn, to: "Added more detail")
        #expect(checkIn.note == "Added more detail")

        // Reschedule
        let newDate = Calendar.current.date(byAdding: .day, value: 7, to: Date())!
        try service.reschedule(checkIn, to: newDate, note: "Pushed back a week")
        #expect(checkIn.status == .scheduled)
        #expect(checkIn.note == "Pushed back a week")

        // Complete
        try service.markCompleted(checkIn, note: "All done")
        #expect(checkIn.status == .completed)
        #expect(checkIn.note == "All done")

        // Delete
        try service.delete(checkIn, from: work)
        #expect(work.checkIns?.isEmpty == true)
    }

    @Test("Multiple check-ins on same work")
    func multipleCheckInsOnSameWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", workType: .practice)
        context.insert(work)
        try context.save()

        let service = WorkCheckInService(context: context)

        let date1 = TestCalendar.date(year: 2025, month: 3, day: 10)
        let date2 = TestCalendar.date(year: 2025, month: 3, day: 17)
        let date3 = TestCalendar.date(year: 2025, month: 3, day: 24)

        let ci1 = try service.createCheckIn(for: work, date: date1, purpose: "Week 1")
        let ci2 = try service.createCheckIn(for: work, date: date2, purpose: "Week 2")
        let ci3 = try service.createCheckIn(for: work, date: date3, purpose: "Week 3")

        #expect(work.checkIns?.count == 3)

        // Complete first, skip second, leave third scheduled
        try service.markCompleted(ci1)
        try service.skip(ci2, note: "Conflict")

        #expect(ci1.status == .completed)
        #expect(ci2.status == .skipped)
        #expect(ci3.status == .scheduled)
    }
}

#endif
