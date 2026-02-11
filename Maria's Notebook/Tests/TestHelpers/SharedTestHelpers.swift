#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Container Factory

struct TestContainerFactory {

    @MainActor
    static func makeContainer(for models: [any PersistentModel.Type]) throws -> ModelContainer {
        return try makeTestContainer(for: models)
    }

    @MainActor
    static func makeStandardContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @MainActor
    static func makeContainerWithContext(for models: [any PersistentModel.Type]) throws -> (ModelContainer, ModelContext) {
        let container = try makeContainer(for: models)
        let context = ModelContext(container)
        return (container, context)
    }
}

// MARK: - Test Entity Builders

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
        let lesson = Lesson(
            name: name,
            lessonType: "Standard",
            subject: subject,
            subheading: "Test Subheading",
            description: "Test Description",
            body: "Test Body",
            materials: "Test Materials",
            group: group
        )
        context.insert(lesson)
        try context.save()
        return lesson
    }

    func buildStudentLesson(
        lesson: Lesson,
        students: [Student],
        scheduledFor: Date? = nil,
        givenAt: Date? = nil
    ) throws -> StudentLesson {
        let studentLesson = makeTestStudentLesson(
            lessonID: lesson.id,
            studentIDs: students.map { $0.id },
            scheduledFor: scheduledFor,
            givenAt: givenAt
        )
        studentLesson.lesson = lesson
        studentLesson.students = students
        context.insert(studentLesson)
        try context.save()
        return studentLesson
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
        let work = makeTestWorkModel(studentID: studentID, title: title)
        if let lessonID = lessonID {
            work.lessonID = lessonID
        }
        context.insert(work)
        try context.save()
        return work
    }
}

// MARK: - Common Test Patterns

struct TestPatterns {

    static func expectSameDayNormalized(_ date1: Date, _ date2: Date, file: StaticString = #file, line: UInt = #line) {
        let normalized1 = Calendar.current.startOfDay(for: date1)
        let normalized2 = Calendar.current.startOfDay(for: date2)
        #expect(normalized1 == normalized2, sourceLocation: SourceLocation(fileID: "", filePath: file.description, line: Int(line), column: 0))
    }

    static func expectThrowsError<T, E: Error>(
        _ expression: @autoclosure () throws -> T,
        ofType errorType: E.Type,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(throws: errorType) {
            _ = try expression()
        }
    }

    static func expectEmpty<T: Collection>(
        _ collection: T,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(collection.isEmpty, sourceLocation: SourceLocation(fileID: "", filePath: file.description, line: Int(line), column: 0))
    }

    static func expectCount<T: Collection>(
        _ collection: T,
        equals expected: Int,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(collection.count == expected, sourceLocation: SourceLocation(fileID: "", filePath: file.description, line: Int(line), column: 0))
    }
}

// MARK: - Error Description Test Helper

struct ErrorDescriptionTester {

    static func testErrorDescription<E: LocalizedError>(
        _ error: E,
        containsSubstring substring: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        let description = error.errorDescription ?? ""
        #expect(description.contains(substring), sourceLocation: SourceLocation(fileID: "", filePath: file.description, line: Int(line), column: 0))
    }

    static func testErrorDescriptionEquals<E: LocalizedError>(
        _ error: E,
        expected: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        #expect(error.errorDescription == expected, sourceLocation: SourceLocation(fileID: "", filePath: file.description, line: Int(line), column: 0))
    }
}

// MARK: - Status Cycling Test Helper

struct StatusCycleTester {

    static func testStatusCycle(
        from: AttendanceStatus,
        to: AttendanceStatus,
        using viewModel: AttendanceViewModel,
        student: Student,
        context: ModelContext
    ) {
        let record = makeTestAttendanceRecord(studentID: student.id, status: from)
        context.insert(record)
        viewModel.recordsByStudent[student.cloudKitKey] = record
        viewModel.cycleStatus(for: student, modelContext: context)
        #expect(viewModel.recordsByStudent[student.cloudKitKey]?.status == to)
    }
}

// MARK: - Deduplication Test Helpers

struct DeduplicationTester {

    static func testDeduplication<T: PersistentModel>(
        setup: (ModelContext) throws -> Void,
        deduplicateAction: (ModelContext) -> Int,
        verifyDeletedCount expectedDeletedCount: Int,
        verifyRemainingCount expectedRemainingCount: Int,
        context: ModelContext
    ) throws {
        try setup(context)
        let deletedCount = deduplicateAction(context)
        #expect(deletedCount == expectedDeletedCount)
        let remaining = context.safeFetch(FetchDescriptor<T>())
        #expect(remaining.count == expectedRemainingCount)
    }
}

#endif
