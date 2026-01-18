#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("StudentLesson State Management Tests", .serialized)
@MainActor
struct StudentLessonTests {

    // MARK: - Test Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            StudentLesson.self,
            Lesson.self,
            Student.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeLesson(id: UUID = UUID(), name: String = "Test Lesson") -> Lesson {
        return Lesson(id: id, name: name, subject: "Math", group: "A", orderInGroup: 1)
    }

    private func makeStudent(id: UUID = UUID(), firstName: String = "Test", lastName: String = "Student") -> Student {
        return Student(id: id, firstName: firstName, lastName: lastName, birthday: TestCalendar.date(year: 2015, month: 6, day: 15))
    }

    // MARK: - Initialization Tests

    @Test("StudentLesson initializes with UUID-based init")
    func initializesWithUUIDs() {
        let lessonID = UUID()
        let studentID = UUID()

        let sl = StudentLesson(
            lessonID: lessonID,
            studentIDs: [studentID]
        )

        #expect(sl.lessonID == lessonID.uuidString)
        #expect(sl.studentIDs == [studentID.uuidString])
        #expect(sl.scheduledFor == nil)
        #expect(sl.givenAt == nil)
        #expect(sl.isPresented == false)
    }

    @Test("StudentLesson initializes with relationship-based init")
    func initializesWithRelationships() {
        let lesson = makeLesson(name: "Addition Lesson")
        let student = makeStudent(firstName: "Alice", lastName: "Anderson")

        let sl = StudentLesson(
            lesson: lesson,
            students: [student]
        )

        #expect(sl.lessonID == lesson.id.uuidString)
        #expect(sl.studentIDs == [student.id.uuidString])
        #expect(sl.lesson?.id == lesson.id)
        #expect(sl.students.count == 1)
        #expect(sl.students[0].id == student.id)
    }

    @Test("StudentLesson stores multiple student IDs correctly")
    func storesMultipleStudents() {
        let student1 = UUID()
        let student2 = UUID()
        let student3 = UUID()

        let sl = StudentLesson(
            lessonID: UUID(),
            studentIDs: [student1, student2, student3]
        )

        #expect(sl.studentIDs.count == 3)
        #expect(sl.studentIDs.contains(student1.uuidString))
        #expect(sl.studentIDs.contains(student2.uuidString))
        #expect(sl.studentIDs.contains(student3.uuidString))
    }

    // MARK: - Scheduling State Tests

    @Test("StudentLesson isScheduled returns false when scheduledFor is nil")
    func isScheduledFalseWhenNil() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])

        #expect(sl.isScheduled == false)
        #expect(sl.scheduledFor == nil)
    }

    @Test("StudentLesson isScheduled returns true when scheduledFor is set")
    func isScheduledTrueWhenSet() {
        let date = TestCalendar.date(year: 2025, month: 2, day: 15)
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [], scheduledFor: date)

        #expect(sl.isScheduled == true)
        #expect(sl.scheduledFor != nil)
    }

    @Test("StudentLesson scheduledForDay is set correctly when scheduling")
    func scheduledForDaySetCorrectly() {
        let date = TestCalendar.date(year: 2025, month: 2, day: 15, hour: 14, minute: 30)
        let expectedDay = TestCalendar.startOfDay(year: 2025, month: 2, day: 15)

        let sl = StudentLesson(lessonID: UUID(), studentIDs: [], scheduledFor: date)

        #expect(sl.scheduledForDay == expectedDay)
    }

    @Test("StudentLesson scheduledForDay updates when scheduledFor changes via setScheduledFor")
    func scheduledForDayUpdatesOnChange() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])

        let date1 = TestCalendar.date(year: 2025, month: 2, day: 15, hour: 10, minute: 0)
        // Use setScheduledFor method to properly update both fields
        // (didSet doesn't fire reliably on @Model properties in SwiftData)
        sl.setScheduledFor(date1, using: Calendar.current)

        let expectedDay1 = TestCalendar.startOfDay(year: 2025, month: 2, day: 15)
        #expect(sl.scheduledForDay == expectedDay1)

        let date2 = TestCalendar.date(year: 2025, month: 2, day: 20, hour: 15, minute: 30)
        sl.setScheduledFor(date2, using: Calendar.current)

        let expectedDay2 = TestCalendar.startOfDay(year: 2025, month: 2, day: 20)
        #expect(sl.scheduledForDay == expectedDay2)
    }

    @Test("StudentLesson scheduledForDay is distantPast when scheduledFor is nil")
    func scheduledForDayDistantPastWhenNil() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])

        #expect(sl.scheduledForDay == Date.distantPast)

        sl.setScheduledFor(TestCalendar.date(year: 2025, month: 2, day: 15), using: Calendar.current)
        #expect(sl.scheduledForDay != Date.distantPast)

        sl.setScheduledFor(nil, using: Calendar.current)
        #expect(sl.scheduledForDay == Date.distantPast)
    }

    @Test("StudentLesson setScheduledFor updates both fields")
    func setScheduledForUpdatesBothFields() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])
        let date = TestCalendar.date(year: 2025, month: 2, day: 15, hour: 14, minute: 30)
        let expectedDay = TestCalendar.startOfDay(year: 2025, month: 2, day: 15)

        sl.setScheduledFor(date, using: Calendar.current)

        #expect(sl.scheduledFor == date)
        #expect(sl.scheduledForDay == expectedDay)
    }

    @Test("StudentLesson setScheduledFor with nil clears both fields")
    func setScheduledForNilClearsBoth() {
        let date = TestCalendar.date(year: 2025, month: 2, day: 15)
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [], scheduledFor: date)

        #expect(sl.scheduledFor != nil)
        #expect(sl.scheduledForDay != Date.distantPast)

        sl.setScheduledFor(nil, using: Calendar.current)

        #expect(sl.scheduledFor == nil)
        #expect(sl.scheduledForDay == Date.distantPast)
    }

    // MARK: - Presentation State Tests

    @Test("StudentLesson isGiven returns false when not presented")
    func isGivenFalseWhenNotPresented() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])

        #expect(sl.isGiven == false)
    }

    @Test("StudentLesson isGiven returns true when isPresented is true")
    func isGivenTrueWhenPresented() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [], isPresented: true)

        #expect(sl.isGiven == true)
    }

    @Test("StudentLesson isGiven returns true when givenAt is set")
    func isGivenTrueWhenGivenAtSet() {
        let date = TestCalendar.date(year: 2025, month: 2, day: 15)
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [], givenAt: date)

        #expect(sl.isGiven == true)
    }

    @Test("StudentLesson isGiven returns true when both isPresented and givenAt are set")
    func isGivenTrueWhenBothSet() {
        let date = TestCalendar.date(year: 2025, month: 2, day: 15)
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [], givenAt: date, isPresented: true)

        #expect(sl.isGiven == true)
    }

    // MARK: - State Transition Tests

    @Test("StudentLesson transitions from unscheduled to scheduled")
    func transitionsToScheduled() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])

        #expect(sl.isScheduled == false)
        #expect(sl.isGiven == false)

        sl.scheduledFor = TestCalendar.date(year: 2025, month: 2, day: 20)

        #expect(sl.isScheduled == true)
        #expect(sl.isGiven == false)
    }

    @Test("StudentLesson transitions from scheduled to presented")
    func transitionsToPresented() {
        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [], scheduledFor: scheduledDate)

        #expect(sl.isScheduled == true)
        #expect(sl.isGiven == false)

        sl.givenAt = TestCalendar.date(year: 2025, month: 2, day: 15)
        sl.isPresented = true

        #expect(sl.isScheduled == true)
        #expect(sl.isGiven == true)
    }

    @Test("StudentLesson can be presented without being scheduled first")
    func presentsWithoutScheduling() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])

        #expect(sl.isScheduled == false)
        #expect(sl.isGiven == false)

        sl.givenAt = Date()
        sl.isPresented = true

        #expect(sl.isScheduled == false)
        #expect(sl.isGiven == true)
    }

    // MARK: - Denormalized Fields Tests

    @Test("StudentLesson normalizeDenormalizedFields updates scheduledForDay")
    func normalizesDenormalizedFields() {
        let date = TestCalendar.date(year: 2025, month: 2, day: 15, hour: 14, minute: 30)
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])

        sl.scheduledFor = date
        // Manually corrupt the denormalized field
        sl.scheduledForDay = Date.distantPast

        #expect(sl.scheduledForDay == Date.distantPast)

        sl.normalizeDenormalizedFields()

        let expectedDay = TestCalendar.startOfDay(year: 2025, month: 2, day: 15)
        #expect(sl.scheduledForDay == expectedDay)
    }

    @Test("StudentLesson normalizeDenormalizedFields sets distantPast when nil")
    func normalizesWithNilScheduledFor() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])
        sl.scheduledFor = nil
        sl.scheduledForDay = Date() // Corrupt

        sl.normalizeDenormalizedFields()

        #expect(sl.scheduledForDay == Date.distantPast)
    }

    // MARK: - Snapshot Tests

    @Test("StudentLesson snapshot captures all state")
    func snapshotCapturesState() {
        let lessonID = UUID()
        let studentID = UUID()
        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let givenDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        let sl = StudentLesson(
            lessonID: lessonID,
            studentIDs: [studentID],
            scheduledFor: scheduledDate,
            givenAt: givenDate,
            isPresented: true,
            notes: "Test notes",
            needsPractice: true,
            needsAnotherPresentation: false,
            followUpWork: "Practice problems"
        )

        let snapshot = sl.snapshot()

        #expect(snapshot.id == sl.id)
        #expect(snapshot.lessonID == lessonID)
        #expect(snapshot.studentIDs == [studentID])
        #expect(snapshot.scheduledFor == scheduledDate)
        #expect(snapshot.givenAt == givenDate)
        #expect(snapshot.isPresented == true)
        #expect(snapshot.notes == "Test notes")
        #expect(snapshot.needsPractice == true)
        #expect(snapshot.needsAnotherPresentation == false)
        #expect(snapshot.followUpWork == "Practice problems")
        #expect(snapshot.isScheduled == true)
        #expect(snapshot.isGiven == true)
    }

    // MARK: - Persistence Tests

    @Test("StudentLesson persists and retrieves from ModelContext")
    func persistsToModelContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let studentID = UUID()
        let sl = StudentLesson(lessonID: lessonID, studentIDs: [studentID])

        context.insert(sl)
        try context.save()

        // Fetch using FetchDescriptor without predicate, then filter
        let descriptor = FetchDescriptor<StudentLesson>()
        let allFetched = try context.fetch(descriptor)
        let fetched = allFetched.filter { $0.id == sl.id }

        #expect(fetched.count == 1)
        #expect(fetched[0].id == sl.id)
        #expect(fetched[0].lessonID == lessonID.uuidString)
        #expect(fetched[0].studentIDs == [studentID.uuidString])
    }

    @Test("StudentLesson scheduled date persists correctly")
    func scheduledDatePersists() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let date = TestCalendar.date(year: 2025, month: 2, day: 15, hour: 10, minute: 30)
        let expectedDay = TestCalendar.startOfDay(year: 2025, month: 2, day: 15)

        let sl = StudentLesson(lessonID: UUID(), studentIDs: [], scheduledFor: date)
        context.insert(sl)
        try context.save()

        // Fetch using FetchDescriptor without predicate, then filter
        let descriptor = FetchDescriptor<StudentLesson>()
        let allFetched = try context.fetch(descriptor)
        let fetched = allFetched.filter { $0.id == sl.id }

        #expect(fetched.count == 1)
        #expect(fetched[0].scheduledFor == date)
        #expect(fetched[0].scheduledForDay == expectedDay)
    }

    // MARK: - Edge Cases

    @Test("StudentLesson handles empty student list")
    func handlesEmptyStudentList() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])

        #expect(sl.studentIDs.isEmpty)
    }

    @Test("StudentLesson handles date edge cases")
    func handlesDateEdgeCases() {
        let farFuture = TestCalendar.date(year: 2099, month: 12, day: 31)
        let farPast = TestCalendar.date(year: 1900, month: 1, day: 1)

        let sl1 = StudentLesson(lessonID: UUID(), studentIDs: [], scheduledFor: farFuture)
        #expect(sl1.scheduledFor == farFuture)

        let sl2 = StudentLesson(lessonID: UUID(), studentIDs: [], givenAt: farPast)
        #expect(sl2.givenAt == farPast)
    }
}

#endif
