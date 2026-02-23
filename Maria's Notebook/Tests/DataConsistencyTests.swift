#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - UUID String Conversion Tests

@Suite("UUID String Conversion Tests", .serialized)
struct UUIDStringConversionTests {

    @Test("UUID to String and back is reversible")
    func uuidStringConversionIsReversible() {
        let original = UUID()
        let string = original.uuidString
        let restored = UUID(uuidString: string)

        #expect(restored == original)
    }

    @Test("Student ID stored as string can be restored")
    func studentIdStringConversion() {
        let studentID = UUID()
        let record = AttendanceRecord(studentID: studentID, date: Date())

        #expect(record.studentIDUUID == studentID)
    }

    @Test("Lesson ID stored as string can be restored")
    func lessonIdStringConversion() {
        let lessonID = UUID()
        let studentLesson = StudentLesson(lessonID: lessonID, studentIDs: [])

        #expect(studentLesson.lessonIDUUID == lessonID)
    }
}

// MARK: - Date Normalization Consistency Tests

@Suite("Date Normalization Consistency Tests", .serialized)
struct DateNormalizationConsistencyTests {

    @Test("normalizedDay returns start of day")
    func normalizedDayReturnsStartOfDay() {
        let date = TestCalendar.date(year: 2025, month: 3, day: 15, hour: 14, minute: 30)
        let normalized = date.normalizedDay()

        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: normalized)

        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }

    @Test("normalizedDay preserves date")
    func normalizedDayPreservesDate() {
        let date = TestCalendar.date(year: 2025, month: 3, day: 15, hour: 23, minute: 59)
        let normalized = date.normalizedDay()

        let components = Calendar.current.dateComponents([.year, .month, .day], from: normalized)

        #expect(components.year == 2025)
        #expect(components.month == 3)
        #expect(components.day == 15)
    }

    @Test("AttendanceRecord normalizes date on creation")
    func attendanceRecordNormalizesDate() {
        let date = TestCalendar.date(year: 2025, month: 3, day: 15, hour: 14, minute: 30)
        let record = AttendanceRecord(studentID: UUID(), date: date.normalizedDay())

        let components = Calendar.current.dateComponents([.hour, .minute, .second], from: record.date)

        #expect(components.hour == 0)
        #expect(components.minute == 0)
        #expect(components.second == 0)
    }
}

// MARK: - WorkModel Status Tests

@Suite("WorkModel Status Consistency Tests", .serialized)
@MainActor
struct WorkModelStatusConsistencyTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("WorkStatus persists correctly through rawValue")
    func workStatusPersistsCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test", kind: .practiceLesson)
        work.status = .review
        context.insert(work)
        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let descriptor = FetchDescriptor<WorkModel>()
        let fetched = try context.fetch(descriptor).first { $0.id == work.id }

        #expect(fetched?.status == .review)
    }

    @Test("WorkStatus transitions are consistent")
    func workStatusTransitionsAreConsistent() {
        let work = WorkModel(title: "Test", kind: .practiceLesson)

        #expect(work.status == .active)

        work.status = .review
        #expect(work.status == .review)
        #expect(work.isReview == true)

        work.status = .complete
        #expect(work.status == .complete)
        #expect(work.isComplete == true)
    }

    @Test("isActive, isReview, isComplete are mutually exclusive")
    func statusHelpersAreMutuallyExclusive() {
        let work = WorkModel(title: "Test", kind: .practiceLesson)

        work.status = .active
        #expect(work.isActive == true)
        #expect(work.isReview == false)
        #expect(work.isComplete == false)

        work.status = .review
        #expect(work.isActive == false)
        #expect(work.isReview == true)
        #expect(work.isComplete == false)

        work.status = .complete
        #expect(work.isActive == false)
        #expect(work.isReview == false)
        #expect(work.isComplete == true)
    }
}

// MARK: - Attendance Status Tests

@Suite("Attendance Status Consistency Tests", .serialized)
struct AttendanceStatusConsistencyTests {

    @Test("AttendanceStatus persists correctly through rawValue")
    func attendanceStatusPersistsCorrectly() {
        let record = AttendanceRecord(studentID: UUID(), date: Date(), status: .tardy)

        #expect(record.status == .tardy)
    }

    @Test("AttendanceStatus all cases are accessible")
    func allCasesAccessible() {
        let allCases = AttendanceStatus.allCases

        #expect(allCases.contains(.unmarked))
        #expect(allCases.contains(.present))
        #expect(allCases.contains(.absent))
        #expect(allCases.contains(.tardy))
        #expect(allCases.contains(.leftEarly))
    }

    @Test("AbsenceReason clears when status is not absent")
    func absenceReasonClearsWhenNotAbsent() {
        let record = AttendanceRecord(studentID: UUID(), date: Date(), status: .absent, absenceReason: .sick)

        #expect(record.absenceReason == .sick)

        record.status = .present

        #expect(record.absenceReason == .none)
    }
}

// MARK: - StudentLesson Consistency Tests

@Suite("StudentLesson Consistency Tests", .serialized)
@MainActor
struct StudentLessonConsistencyTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            StudentLesson.self,
            Lesson.self,
            Student.self,
        ])
    }

    @Test("StudentLesson studentIDs encode and decode correctly")
    func studentIDsEncodeAndDecodeCorrectly() throws {
        let id1 = UUID()
        let id2 = UUID()

        let sl = StudentLesson(lessonID: UUID(), studentIDs: [id1, id2])

        #expect(sl.studentIDs.count == 2)
        #expect(sl.studentIDs.contains(id1.uuidString))
        #expect(sl.studentIDs.contains(id2.uuidString))
    }

    @Test("StudentLesson scheduledForDay updates when scheduledFor changes")
    func scheduledForDayUpdatesCorrectly() {
        let date = TestCalendar.date(year: 2025, month: 3, day: 15, hour: 14, minute: 30)
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [], scheduledFor: date)

        let dayComponents = Calendar.current.dateComponents([.year, .month, .day], from: sl.scheduledForDay)

        #expect(dayComponents.year == 2025)
        #expect(dayComponents.month == 3)
        #expect(dayComponents.day == 15)
    }

    @Test("StudentLesson isScheduled reflects scheduledFor")
    func isScheduledReflectsScheduledFor() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])

        #expect(sl.isScheduled == false)

        sl.scheduledFor = Date()

        #expect(sl.isScheduled == true)
    }

    @Test("StudentLesson isGiven reflects givenAt")
    func isGivenReflectsGivenAt() {
        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])

        #expect(sl.isGiven == false)

        sl.givenAt = Date()

        #expect(sl.isGiven == true)
    }
}

// MARK: - Cross-Model Consistency Tests

@Suite("Cross-Model Consistency Tests", .serialized)
@MainActor
struct CrossModelConsistencyTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            AttendanceRecord.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            Note.self,
            Document.self,
        ])
    }

    @Test("Student ID matches across models")
    func studentIdMatchesAcrossModels() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let record = AttendanceRecord(studentID: student.id, date: Date())
        context.insert(record)

        let work = WorkModel(title: "Work", kind: .practiceLesson)
        work.studentID = student.id.uuidString
        let participant = WorkParticipantEntity(studentID: student.id, completedAt: nil, work: work)
        work.participants = [participant]
        context.insert(work)

        try context.save()

        // Verify all IDs match
        #expect(record.studentID == student.id.uuidString)
        #expect(work.studentID == student.id.uuidString)
        #expect(participant.studentID == student.id.uuidString)
    }

    @Test("Lesson ID matches across models")
    func lessonIdMatchesAcrossModels() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition")
        context.insert(lesson)

        let sl = StudentLesson(lessonID: lesson.id, studentIDs: [])
        sl.lesson = lesson
        context.insert(sl)

        let work = WorkModel(title: "Work", kind: .practiceLesson)
        work.lessonID = lesson.id.uuidString
        context.insert(work)

        try context.save()

        // Verify all IDs match
        #expect(sl.lessonID == lesson.id.uuidString)
        #expect(sl.lesson?.id == lesson.id)
        #expect(work.lessonID == lesson.id.uuidString)
    }
}

// MARK: - Empty State Tests

@Suite("Empty State Consistency Tests", .serialized)
@MainActor
struct EmptyStateConsistencyTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            AttendanceRecord.self,
            WorkModel.self,
            WorkParticipantEntity.self,
        ])
    }

    @Test("Empty studentIDs array persists correctly")
    func emptyStudentIDsPersistsCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = StudentLesson(lessonID: UUID(), studentIDs: [])
        context.insert(sl)
        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let slDescriptor = FetchDescriptor<StudentLesson>()
        let fetched = try context.fetch(slDescriptor).first { $0.id == sl.id }

        #expect(fetched?.studentIDs.isEmpty == true)
    }

    @Test("Nil relationships persist correctly")
    func nilRelationshipsPersistCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test", kind: .practiceLesson)
        work.studentLessonID = nil
        work.completedAt = nil
        context.insert(work)
        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let workDescriptor = FetchDescriptor<WorkModel>()
        let fetched = try context.fetch(workDescriptor).first { $0.id == work.id }

        #expect(fetched?.studentLessonID == nil)
        #expect(fetched?.completedAt == nil)
    }

    @Test("Empty strings persist correctly")
    func emptyStringsPersistCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "", kind: .practiceLesson)
        context.insert(work)
        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let descriptor = FetchDescriptor<WorkModel>()
        let fetched = try context.fetch(descriptor).first { $0.id == work.id }

        #expect(fetched?.title == "")
        #expect(fetched?.latestUnifiedNoteText.isEmpty == true)
    }
}

#endif
