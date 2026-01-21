#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Fetch Tests

@Suite("StudentRepository Fetch Tests", .serialized)
@MainActor
struct StudentRepositoryFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("fetchStudent returns student by ID")
    func fetchStudentReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)
        try context.save()

        let repository = StudentRepository(context: context)
        let fetched = repository.fetchStudent(id: student.id)

        #expect(fetched != nil)
        #expect(fetched?.id == student.id)
        #expect(fetched?.firstName == "Alice")
        #expect(fetched?.lastName == "Smith")
    }

    @Test("fetchStudent returns nil for missing ID")
    func fetchStudentReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = StudentRepository(context: context)
        let fetched = repository.fetchStudent(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchStudents returns all when no predicate")
    func fetchStudentsReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)
        try context.save()

        let repository = StudentRepository(context: context)
        let fetched = repository.fetchStudents()

        #expect(fetched.count == 3)
    }

    @Test("fetchStudents sorts by lastName then firstName by default")
    func fetchStudentsSortsByName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Zoe", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Alice", lastName: "Brown")
        let student3 = makeTestStudent(firstName: "Bob", lastName: "Anderson")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)
        try context.save()

        let repository = StudentRepository(context: context)
        let fetched = repository.fetchStudents()

        #expect(fetched[0].lastName == "Anderson")
        #expect(fetched[0].firstName == "Bob")
        #expect(fetched[1].lastName == "Anderson")
        #expect(fetched[1].firstName == "Zoe")
        #expect(fetched[2].lastName == "Brown")
    }

    @Test("fetchStudents respects predicate")
    func fetchStudentsRespectsPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith", level: .lower)
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones", level: .upper)
        context.insert(student1)
        context.insert(student2)
        try context.save()

        let repository = StudentRepository(context: context)
        let predicate = #Predicate<Student> { $0.levelRaw == Student.Level.lower.rawValue }
        let fetched = repository.fetchStudents(predicate: predicate)

        #expect(fetched.count == 1)
        #expect(fetched[0].level == .lower)
    }

    @Test("fetchStudents handles empty database")
    func fetchStudentsHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = StudentRepository(context: context)
        let fetched = repository.fetchStudents()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Create Tests

@Suite("StudentRepository Create Tests", .serialized)
@MainActor
struct StudentRepositoryCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("createStudent creates student with required fields")
    func createStudentCreatesWithRequiredFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let birthday = TestCalendar.date(year: 2015, month: 6, day: 15)

        let repository = StudentRepository(context: context)
        let student = repository.createStudent(
            firstName: "Alice",
            lastName: "Smith",
            birthday: birthday
        )

        #expect(student.firstName == "Alice")
        #expect(student.lastName == "Smith")
        #expect(student.birthday == birthday)
        #expect(student.level == .lower) // Default
    }

    @Test("createStudent sets optional fields when provided")
    func createStudentSetsOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let birthday = TestCalendar.date(year: 2012, month: 3, day: 20)
        let dateStarted = TestCalendar.date(year: 2024, month: 9, day: 1)

        let repository = StudentRepository(context: context)
        let student = repository.createStudent(
            firstName: "Bob",
            lastName: "Jones",
            birthday: birthday,
            nickname: "Bobby",
            level: .upper,
            dateStarted: dateStarted
        )

        #expect(student.nickname == "Bobby")
        #expect(student.level == .upper)
        #expect(student.dateStarted == dateStarted)
    }

    @Test("createStudent persists to context")
    func createStudentPersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = StudentRepository(context: context)
        let student = repository.createStudent(
            firstName: "Alice",
            lastName: "Smith",
            birthday: TestCalendar.date(year: 2015, month: 6, day: 15)
        )

        // Fetch from context to verify persistence
        let fetched = repository.fetchStudent(id: student.id)

        #expect(fetched != nil)
        #expect(fetched?.id == student.id)
    }
}

// MARK: - Update Tests

@Suite("StudentRepository Update Tests", .serialized)
@MainActor
struct StudentRepositoryUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("updateStudent updates firstName")
    func updateStudentUpdatesFirstName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)
        try context.save()

        let repository = StudentRepository(context: context)
        let result = repository.updateStudent(id: student.id, firstName: "Alicia")

        #expect(result == true)
        #expect(student.firstName == "Alicia")
    }

    @Test("updateStudent updates lastName")
    func updateStudentUpdatesLastName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)
        try context.save()

        let repository = StudentRepository(context: context)
        let result = repository.updateStudent(id: student.id, lastName: "Johnson")

        #expect(result == true)
        #expect(student.lastName == "Johnson")
    }

    @Test("updateStudent updates level")
    func updateStudentUpdatesLevel() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(level: .lower)
        context.insert(student)
        try context.save()

        let repository = StudentRepository(context: context)
        let result = repository.updateStudent(id: student.id, level: .upper)

        #expect(result == true)
        #expect(student.level == .upper)
    }

    @Test("updateStudent clears nickname when empty string provided")
    func updateStudentClearsNickname() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(nickname: "Bobby")
        context.insert(student)
        try context.save()

        let repository = StudentRepository(context: context)
        let result = repository.updateStudent(id: student.id, nickname: "")

        #expect(result == true)
        #expect(student.nickname == nil)
    }

    @Test("updateStudent returns false for missing ID")
    func updateStudentReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = StudentRepository(context: context)
        let result = repository.updateStudent(id: UUID(), firstName: "NewName")

        #expect(result == false)
    }

    @Test("updateStudent only changes specified fields")
    func updateStudentOnlyChangesSpecifiedFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let birthday = TestCalendar.date(year: 2015, month: 6, day: 15)
        let student = makeTestStudent(firstName: "Alice", lastName: "Smith", birthday: birthday, level: .lower)
        context.insert(student)
        try context.save()

        let repository = StudentRepository(context: context)
        _ = repository.updateStudent(id: student.id, firstName: "Alicia")

        #expect(student.firstName == "Alicia")
        #expect(student.lastName == "Smith") // Unchanged
        #expect(student.birthday == birthday) // Unchanged
        #expect(student.level == .lower) // Unchanged
    }
}

// MARK: - Delete Tests

@Suite("StudentRepository Delete Tests", .serialized)
@MainActor
struct StudentRepositoryDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            AttendanceRecord.self,
            Note.self,
        ])
    }

    @Test("deleteStudent removes student from context")
    func deleteStudentRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)
        try context.save()

        let studentID = student.id

        let repository = StudentRepository(context: context)
        try repository.deleteStudent(id: studentID)

        let fetched = repository.fetchStudent(id: studentID)
        #expect(fetched == nil)
    }

    @Test("deleteStudent does nothing for missing ID")
    func deleteStudentDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = StudentRepository(context: context)
        try repository.deleteStudent(id: UUID())

        // Should not throw - just silently does nothing
    }
}

#endif
