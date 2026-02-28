#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Container Factory

/// Creates an in-memory ModelContainer with the specified model types for testing.
/// This ensures test isolation — each test gets a fresh database.
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
        LessonAssignment.self,
        LessonPresentation.self,
        AttendanceRecord.self,
        WorkModel.self,
        WorkParticipantEntity.self,
        WorkCheckIn.self,
        Note.self,
        NoteStudentLink.self,
        GroupTrack.self,
        StudentTrackEnrollment.self,
        NonSchoolDay.self,
        SchoolDayOverride.self,
    ])
}

// MARK: - Model Factories

/// Creates a test Student with sensible defaults
func makeTestStudent(
    id: UUID = UUID(),
    firstName: String = "Test",
    lastName: String = "Student",
    birthday: Date = Calendar.current.date(from: DateComponents(year: 2015, month: 6, day: 15))!,
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

/// Creates a test LessonAssignment in draft state
func makeTestLessonAssignment(
    id: UUID = UUID(),
    lessonID: UUID = UUID(),
    studentIDs: [UUID] = [],
    scheduledFor: Date? = nil,
    presentedAt: Date? = nil,
    notes: String = ""
) -> LessonAssignment {
    let la: LessonAssignment
    if let presentedAt = presentedAt {
        la = PresentationFactory.makePresented(
            lessonID: lessonID,
            studentIDs: studentIDs,
            presentedAt: presentedAt,
            id: id
        )
    } else if let scheduledFor = scheduledFor {
        la = PresentationFactory.makeScheduled(
            lessonID: lessonID,
            studentIDs: studentIDs,
            scheduledFor: scheduledFor,
            id: id
        )
    } else {
        la = PresentationFactory.makeDraft(
            lessonID: lessonID,
            studentIDs: studentIDs,
            id: id
        )
    }
    la.notes = notes
    return la
}

/// Creates a test AttendanceRecord with sensible defaults
func makeTestAttendanceRecord(
    id: UUID = UUID(),
    studentID: UUID,
    date: Date = Calendar.current.date(from: DateComponents(year: 2025, month: 1, day: 15))!,
    status: AttendanceStatus = .unmarked,
    absenceReason: AbsenceReason = .none
) -> AttendanceRecord {
    return AttendanceRecord(
        id: id,
        studentID: studentID,
        date: date.normalizedDay(),
        status: status,
        absenceReason: absenceReason
    )
}

/// Creates a test WorkModel with sensible defaults
func makeTestWorkModel(
    id: UUID = UUID(),
    title: String = "Test Work",
    kind: WorkKind = .practiceLesson,
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
        kind: kind,
        completedAt: completedAt,
        status: status,
        assignedAt: assignedAt,
        lastTouchedAt: lastTouchedAt,
        dueAt: dueAt,
        studentID: studentID,
        lessonID: lessonID
    )
}

// MARK: - Test Entity Builder

struct TestEntityBuilder {

    let context: ModelContext

    func buildStudent(
        firstName: String = "Test",
        lastName: String = "Student",
        birthday: Date? = nil
    ) throws -> Student {
        let student = makeTestStudent(firstName: firstName, lastName: lastName)
        if let birthday = birthday {
            student.birthday = birthday
        }
        context.insert(student)
        try context.save()
        return student
    }

    func buildLesson(
        name: String = "Test Lesson",
        subject: String = "Math",
        group: String = "Algebra"
    ) throws -> Lesson {
        let lesson = makeTestLesson(name: name, subject: subject, group: group)
        context.insert(lesson)
        try context.save()
        return lesson
    }

    func buildLessonAssignment(
        lesson: Lesson,
        students: [Student],
        scheduledFor: Date? = nil,
        presentedAt: Date? = nil
    ) throws -> LessonAssignment {
        let la = makeTestLessonAssignment(
            lessonID: lesson.id,
            studentIDs: students.map { $0.id },
            scheduledFor: scheduledFor,
            presentedAt: presentedAt
        )
        PresentationFactory.attachRelationships(to: la, lesson: lesson, students: students)
        context.insert(la)
        try context.save()
        return la
    }

    func buildAttendanceRecord(
        studentID: UUID,
        date: Date,
        status: AttendanceStatus = .unmarked
    ) throws -> AttendanceRecord {
        let record = makeTestAttendanceRecord(studentID: studentID, date: date, status: status)
        context.insert(record)
        try context.save()
        return record
    }

    func buildWorkModel(
        studentID: String? = nil,
        lessonID: String? = nil,
        title: String = "Test Work"
    ) throws -> WorkModel {
        let work = makeTestWorkModel(
            title: title,
            studentID: studentID ?? "",
            lessonID: lessonID ?? ""
        )
        context.insert(work)
        try context.save()
        return work
    }
}

// MARK: - Assertion Helpers

/// Asserts that two dates are equal when normalized to start of day
func expectSameDay(_ date1: Date, _ date2: Date, sourceLocation: SourceLocation = #_sourceLocation) {
    let d1 = AppCalendar.startOfDay(date1)
    let d2 = AppCalendar.startOfDay(date2)
    #expect(d1 == d2, sourceLocation: sourceLocation)
}

/// Asserts that a collection contains exactly the expected count
func expectCount<T: Collection>(_ collection: T, equals expected: Int, sourceLocation: SourceLocation = #_sourceLocation) {
    #expect(collection.count == expected, sourceLocation: sourceLocation)
}

// MARK: - Date Helpers

/// Creates a date from year/month/day components
func testDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = 0
    return Calendar.current.date(from: components)!
}

#endif
