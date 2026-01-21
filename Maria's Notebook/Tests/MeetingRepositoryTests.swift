#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Fetch Tests

@Suite("MeetingRepository Fetch Tests", .serialized)
@MainActor
struct MeetingRepositoryFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            StudentMeeting.self,
            Note.self,
        ])
    }

    @Test("fetchMeeting returns meeting by ID")
    func fetchMeetingReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meeting = StudentMeeting(studentID: studentID)
        context.insert(meeting)
        try context.save()

        let repository = MeetingRepository(context: context)
        let fetched = repository.fetchMeeting(id: meeting.id)

        #expect(fetched != nil)
        #expect(fetched?.id == meeting.id)
    }

    @Test("fetchMeeting returns nil for missing ID")
    func fetchMeetingReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = MeetingRepository(context: context)
        let fetched = repository.fetchMeeting(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchMeetings returns all when no predicate")
    func fetchMeetingsReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meeting1 = StudentMeeting(studentID: studentID)
        let meeting2 = StudentMeeting(studentID: studentID)
        let meeting3 = StudentMeeting(studentID: studentID)
        context.insert(meeting1)
        context.insert(meeting2)
        context.insert(meeting3)
        try context.save()

        let repository = MeetingRepository(context: context)
        let fetched = repository.fetchMeetings()

        #expect(fetched.count == 3)
    }

    @Test("fetchMeetings sorts by date descending by default")
    func fetchMeetingsSortsByDateDesc() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let oldDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let meeting1 = StudentMeeting(studentID: studentID, date: oldDate)
        let meeting2 = StudentMeeting(studentID: studentID, date: newDate)
        context.insert(meeting1)
        context.insert(meeting2)
        try context.save()

        let repository = MeetingRepository(context: context)
        let fetched = repository.fetchMeetings()

        #expect(fetched[0].date > fetched[1].date)
    }

    @Test("fetchMeetings forStudentID filters correctly")
    func fetchMeetingsForStudentIDFilters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID1 = UUID()
        let studentID2 = UUID()

        let meeting1 = StudentMeeting(studentID: studentID1)
        let meeting2 = StudentMeeting(studentID: studentID2)
        context.insert(meeting1)
        context.insert(meeting2)
        try context.save()

        let repository = MeetingRepository(context: context)
        let fetched = repository.fetchMeetings(forStudentID: studentID1)

        #expect(fetched.count == 1)
        #expect(fetched[0].studentID == studentID1.uuidString)
    }

    @Test("fetchIncompleteMeetings returns incomplete only")
    func fetchIncompleteMeetingsReturnsIncomplete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meeting1 = StudentMeeting(studentID: studentID, completed: false)
        let meeting2 = StudentMeeting(studentID: studentID, completed: true)
        context.insert(meeting1)
        context.insert(meeting2)
        try context.save()

        let repository = MeetingRepository(context: context)
        let fetched = repository.fetchIncompleteMeetings()

        #expect(fetched.count == 1)
        #expect(fetched[0].completed == false)
    }

    @Test("fetchMeetings in date range filters correctly")
    func fetchMeetingsInDateRangeFilters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let startDate = TestCalendar.date(year: 2025, month: 1, day: 15)
        let endDate = TestCalendar.date(year: 2025, month: 1, day: 20)
        let withinRange = TestCalendar.date(year: 2025, month: 1, day: 17)
        let outsideRange = TestCalendar.date(year: 2025, month: 1, day: 25)

        let meeting1 = StudentMeeting(studentID: studentID, date: withinRange)
        let meeting2 = StudentMeeting(studentID: studentID, date: outsideRange)
        context.insert(meeting1)
        context.insert(meeting2)
        try context.save()

        let repository = MeetingRepository(context: context)
        let fetched = repository.fetchMeetings(from: startDate, to: endDate)

        #expect(fetched.count == 1)
    }

    @Test("fetchMeetings handles empty database")
    func fetchMeetingsHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = MeetingRepository(context: context)
        let fetched = repository.fetchMeetings()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Create Tests

@Suite("MeetingRepository Create Tests", .serialized)
@MainActor
struct MeetingRepositoryCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            StudentMeeting.self,
            Note.self,
        ])
    }

    @Test("createMeeting creates meeting with required fields")
    func createMeetingCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()

        let repository = MeetingRepository(context: context)
        let meeting = repository.createMeeting(studentID: studentID)

        #expect(meeting.studentID == studentID.uuidString)
        #expect(meeting.completed == false) // Default
    }

    @Test("createMeeting sets optional fields when provided")
    func createMeetingSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meetingDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        let repository = MeetingRepository(context: context)
        let meeting = repository.createMeeting(
            studentID: studentID,
            date: meetingDate,
            completed: true,
            reflection: "Good progress this week",
            focus: "Math fractions",
            requests: "More practice with division",
            guideNotes: "Consider hands-on activities"
        )

        #expect(meeting.date == meetingDate)
        #expect(meeting.completed == true)
        #expect(meeting.reflection == "Good progress this week")
        #expect(meeting.focus == "Math fractions")
        #expect(meeting.requests == "More practice with division")
        #expect(meeting.guideNotes == "Consider hands-on activities")
    }

    @Test("createMeeting persists to context")
    func createMeetingPersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()

        let repository = MeetingRepository(context: context)
        let meeting = repository.createMeeting(studentID: studentID)

        let fetched = repository.fetchMeeting(id: meeting.id)

        #expect(fetched != nil)
        #expect(fetched?.id == meeting.id)
    }
}

// MARK: - Update Tests

@Suite("MeetingRepository Update Tests", .serialized)
@MainActor
struct MeetingRepositoryUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            StudentMeeting.self,
            Note.self,
        ])
    }

    @Test("updateMeeting updates date")
    func updateMeetingUpdatesDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meeting = StudentMeeting(studentID: studentID)
        context.insert(meeting)
        try context.save()

        let newDate = TestCalendar.date(year: 2025, month: 3, day: 20)

        let repository = MeetingRepository(context: context)
        let result = repository.updateMeeting(id: meeting.id, date: newDate)

        #expect(result == true)
        #expect(meeting.date == newDate)
    }

    @Test("updateMeeting updates completed")
    func updateMeetingUpdatesCompleted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meeting = StudentMeeting(studentID: studentID, completed: false)
        context.insert(meeting)
        try context.save()

        let repository = MeetingRepository(context: context)
        let result = repository.updateMeeting(id: meeting.id, completed: true)

        #expect(result == true)
        #expect(meeting.completed == true)
    }

    @Test("updateMeeting updates reflection")
    func updateMeetingUpdatesReflection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meeting = StudentMeeting(studentID: studentID)
        context.insert(meeting)
        try context.save()

        let repository = MeetingRepository(context: context)
        let result = repository.updateMeeting(id: meeting.id, reflection: "Made great progress")

        #expect(result == true)
        #expect(meeting.reflection == "Made great progress")
    }

    @Test("updateMeeting updates focus")
    func updateMeetingUpdatesFocus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meeting = StudentMeeting(studentID: studentID)
        context.insert(meeting)
        try context.save()

        let repository = MeetingRepository(context: context)
        let result = repository.updateMeeting(id: meeting.id, focus: "Reading comprehension")

        #expect(result == true)
        #expect(meeting.focus == "Reading comprehension")
    }

    @Test("updateMeeting returns false for missing ID")
    func updateMeetingReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = MeetingRepository(context: context)
        let result = repository.updateMeeting(id: UUID(), reflection: "Test")

        #expect(result == false)
    }

    @Test("markCompleted sets completed to true")
    func markCompletedSetsCompletedTrue() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meeting = StudentMeeting(studentID: studentID, completed: false)
        context.insert(meeting)
        try context.save()

        let repository = MeetingRepository(context: context)
        let result = repository.markCompleted(id: meeting.id)

        #expect(result == true)
        #expect(meeting.completed == true)
    }

    @Test("markCompleted returns false for missing ID")
    func markCompletedReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = MeetingRepository(context: context)
        let result = repository.markCompleted(id: UUID())

        #expect(result == false)
    }

    @Test("updateMeeting only changes specified fields")
    func updateMeetingOnlyChangesSpecifiedFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meeting = StudentMeeting(
            studentID: studentID,
            completed: false,
            reflection: "Original reflection",
            focus: "Original focus"
        )
        context.insert(meeting)
        try context.save()

        let repository = MeetingRepository(context: context)
        _ = repository.updateMeeting(id: meeting.id, reflection: "Updated reflection")

        #expect(meeting.reflection == "Updated reflection")
        #expect(meeting.focus == "Original focus") // Unchanged
        #expect(meeting.completed == false) // Unchanged
    }
}

// MARK: - Delete Tests

@Suite("MeetingRepository Delete Tests", .serialized)
@MainActor
struct MeetingRepositoryDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            StudentMeeting.self,
            Note.self,
        ])
    }

    @Test("deleteMeeting removes meeting from context")
    func deleteMeetingRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let meeting = StudentMeeting(studentID: studentID)
        context.insert(meeting)
        try context.save()

        let meetingID = meeting.id

        let repository = MeetingRepository(context: context)
        try repository.deleteMeeting(id: meetingID)

        let fetched = repository.fetchMeeting(id: meetingID)
        #expect(fetched == nil)
    }

    @Test("deleteMeeting does nothing for missing ID")
    func deleteMeetingDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = MeetingRepository(context: context)
        try repository.deleteMeeting(id: UUID())

        // Should not throw
    }
}

#endif
