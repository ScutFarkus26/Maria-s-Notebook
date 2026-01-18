#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Container Factory

/// Creates an in-memory ModelContainer with the specified model types for testing.
/// This ensures test isolation - each test gets a fresh database.
@MainActor
func makeTestContainer(for types: [any PersistentModel.Type]) throws -> ModelContainer {
    let schema = Schema(types)
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

/// Creates a standard container with commonly used models for most tests
@MainActor
func makeStandardTestContainer() throws -> ModelContainer {
    return try makeTestContainer(for: [
        Student.self,
        Lesson.self,
        StudentLesson.self,
        AttendanceRecord.self,
        WorkModel.self,
        WorkParticipantEntity.self,
        WorkCheckIn.self,
        WorkPlanItem.self,
        Note.self,
        GroupTrack.self,
        StudentTrackEnrollment.self,
        LessonPresentation.self,
    ])
}

// MARK: - Model Factories

/// Creates a test Student with sensible defaults
func makeTestStudent(
    id: UUID = UUID(),
    firstName: String = "Test",
    lastName: String = "Student",
    birthday: Date = TestCalendar.date(year: 2015, month: 6, day: 15),
    nickname: String? = nil,
    level: Student.Level = .lower,
    dateStarted: Date? = nil,
    manualOrder: Int = 0
) -> Student {
    return Student(
        id: id,
        firstName: firstName,
        lastName: lastName,
        birthday: birthday,
        nickname: nickname,
        level: level,
        dateStarted: dateStarted,
        manualOrder: manualOrder
    )
}

/// Creates a test Lesson with sensible defaults
func makeTestLesson(
    id: UUID = UUID(),
    name: String = "Test Lesson",
    subject: String = "Math",
    group: String = "Group A",
    orderInGroup: Int = 1,
    sortIndex: Int = 0,
    subheading: String = "",
    writeUp: String = ""
) -> Lesson {
    return Lesson(
        id: id,
        name: name,
        subject: subject,
        group: group,
        orderInGroup: orderInGroup,
        sortIndex: sortIndex,
        subheading: subheading,
        writeUp: writeUp
    )
}

/// Creates a test StudentLesson with sensible defaults
func makeTestStudentLesson(
    id: UUID = UUID(),
    lessonID: UUID = UUID(),
    studentIDs: [UUID] = [],
    scheduledFor: Date? = nil,
    givenAt: Date? = nil,
    isPresented: Bool = false,
    notes: String = ""
) -> StudentLesson {
    return StudentLesson(
        id: id,
        lessonID: lessonID,
        studentIDs: studentIDs,
        scheduledFor: scheduledFor,
        givenAt: givenAt,
        isPresented: isPresented,
        notes: notes
    )
}

/// Creates a StudentLesson from existing Student and Lesson objects
func makeTestStudentLesson(
    student: Student,
    lesson: Lesson,
    scheduledFor: Date? = nil,
    givenAt: Date? = nil,
    isPresented: Bool = false
) -> StudentLesson {
    return StudentLesson(
        lesson: lesson,
        students: [student],
        scheduledFor: scheduledFor,
        givenAt: givenAt,
        isPresented: isPresented
    )
}

/// Creates a test AttendanceRecord with sensible defaults
func makeTestAttendanceRecord(
    id: UUID = UUID(),
    studentID: UUID,
    date: Date = TestCalendar.date(year: 2025, month: 1, day: 15),
    status: AttendanceStatus = .unmarked,
    absenceReason: AbsenceReason = .none,
    note: String? = nil
) -> AttendanceRecord {
    return AttendanceRecord(
        id: id,
        studentID: studentID,
        date: date.normalizedDay(),
        status: status,
        absenceReason: absenceReason,
        note: note
    )
}

/// Creates a test WorkModel with sensible defaults
func makeTestWorkModel(
    id: UUID = UUID(),
    title: String = "Test Work",
    workType: WorkModel.WorkType = .practice,
    completedAt: Date? = nil,
    status: WorkStatus = .active,
    assignedAt: Date = Date(),
    lastTouchedAt: Date? = nil,
    dueAt: Date? = nil,
    studentID: String = "",
    lessonID: String = ""
) -> WorkModel {
    return WorkModel(
        id: id,
        title: title,
        workType: workType,
        completedAt: completedAt,
        status: status,
        assignedAt: assignedAt,
        lastTouchedAt: lastTouchedAt,
        dueAt: dueAt,
        studentID: studentID,
        lessonID: lessonID
    )
}

/// Creates a test GroupTrack with sensible defaults
func makeTestGroupTrack(
    id: UUID = UUID(),
    subject: String = "Math",
    group: String = "Group A"
) -> GroupTrack {
    return GroupTrack(
        id: id,
        subject: subject,
        group: group
    )
}

// MARK: - Assertion Helpers

/// Asserts that two dates are equal when normalized to start of day
func expectSameDay(_ date1: Date, _ date2: Date, sourceLocation: SourceLocation = #_sourceLocation) {
    let d1 = Calendar.current.startOfDay(for: date1)
    let d2 = Calendar.current.startOfDay(for: date2)
    #expect(d1 == d2, sourceLocation: sourceLocation)
}

/// Asserts that a collection contains exactly the expected count
func expectCount<T: Collection>(_ collection: T, equals expected: Int, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(collection.count == expected, sourceLocation: sourceLocation)
}

// MARK: - Test Data Sets

/// Creates a set of test students with varied data
func makeTestStudentSet() -> [Student] {
    return [
        makeTestStudent(firstName: "Alice", lastName: "Anderson", level: .lower, manualOrder: 1),
        makeTestStudent(firstName: "Bob", lastName: "Brown", level: .lower, manualOrder: 2),
        makeTestStudent(firstName: "Charlie", lastName: "Clark", level: .upper, manualOrder: 3),
        makeTestStudent(firstName: "Diana", lastName: "Davis", level: .upper, manualOrder: 4),
        makeTestStudent(firstName: "Eve", lastName: "Evans", level: .lower, manualOrder: 5),
    ]
}

/// Creates a set of test lessons organized by subject and group
func makeTestLessonSet() -> [Lesson] {
    return [
        makeTestLesson(name: "Addition", subject: "Math", group: "Operations", orderInGroup: 1),
        makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations", orderInGroup: 2),
        makeTestLesson(name: "Multiplication", subject: "Math", group: "Operations", orderInGroup: 3),
        makeTestLesson(name: "Reading Basics", subject: "Language", group: "Reading", orderInGroup: 1),
        makeTestLesson(name: "Writing Practice", subject: "Language", group: "Writing", orderInGroup: 1),
    ]
}

#endif
