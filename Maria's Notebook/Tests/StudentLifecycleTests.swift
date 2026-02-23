#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Student Creation Tests

@Suite("Student Creation Tests", .serialized)
@MainActor
struct StudentCreationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            StudentLesson.self,
            Lesson.self,
            AttendanceRecord.self,
            Note.self,
            Document.self,
        ])
    }

    @Test("Student initializes with required fields")
    func initializesWithRequiredFields() {
        let birthday = TestCalendar.date(year: 2015, month: 6, day: 15)
        let student = Student(firstName: "Alice", lastName: "Anderson", birthday: birthday)

        #expect(student.firstName == "Alice")
        #expect(student.lastName == "Anderson")
        #expect(student.birthday == birthday)
    }

    @Test("Student generates unique ID")
    func generatesUniqueId() {
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")

        #expect(student1.id != student2.id)
    }

    @Test("Student level defaults to lower")
    func levelDefaultsToLower() {
        let student = makeTestStudent()

        #expect(student.level == .lower)
    }

    @Test("Student persists to context")
    func persistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)
        try context.save()

        let descriptor = FetchDescriptor<Student>()
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched[0].firstName == "Alice")
        #expect(fetched[0].lastName == "Anderson")
    }

    @Test("Student fullName computed correctly")
    func fullNameComputedCorrectly() {
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")

        #expect(student.fullName == "Alice Anderson")
    }

    @Test("Student can have nickname")
    func canHaveNickname() {
        let student = Student(firstName: "Elizabeth", lastName: "Smith", birthday: Date(), nickname: "Liz")

        #expect(student.nickname == "Liz")
    }

    @Test("Student manualOrder defaults to zero")
    func manualOrderDefaultsToZero() {
        let student = makeTestStudent()

        #expect(student.manualOrder == 0)
    }

    @Test("Student dateStarted is optional")
    func dateStartedIsOptional() {
        let student = makeTestStudent()

        #expect(student.dateStarted == nil)
    }
}

// MARK: - Student Level Tests

@Suite("Student Level Tests", .serialized)
struct StudentLevelTests {

    @Test("Student.Level.lower has correct rawValue")
    func lowerHasCorrectRawValue() {
        #expect(Student.Level.lower.rawValue == "Lower")
    }

    @Test("Student.Level.upper has correct rawValue")
    func upperHasCorrectRawValue() {
        #expect(Student.Level.upper.rawValue == "Upper")
    }

    @Test("Student level can be set to upper")
    func levelCanBeSetToUpper() {
        let student = makeTestStudent(level: .upper)

        #expect(student.level == .upper)
    }

    @Test("Student level can be changed")
    func levelCanBeChanged() {
        let student = makeTestStudent(level: .lower)

        #expect(student.level == .lower)

        student.level = .upper

        #expect(student.level == .upper)
    }
}

// MARK: - Student Relationships Tests

@Suite("Student Relationships Tests", .serialized)
@MainActor
struct StudentRelationshipsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            StudentLesson.self,
            Lesson.self,
            AttendanceRecord.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            Note.self,
            Document.self,
        ])
    }

    @Test("Student can have multiple StudentLessons")
    func canHaveMultipleStudentLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let lesson1 = makeTestLesson(name: "Addition")
        let lesson2 = makeTestLesson(name: "Subtraction")
        context.insert(lesson1)
        context.insert(lesson2)

        let sl1 = StudentLesson(lessonID: lesson1.id, studentIDs: [student.id])
        let sl2 = StudentLesson(lessonID: lesson2.id, studentIDs: [student.id])
        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        // Fetch StudentLessons for this student
        let descriptor = FetchDescriptor<StudentLesson>()
        let allStudentLessons = try context.fetch(descriptor)
        let studentLessons = allStudentLessons.filter { $0.studentIDs.contains(student.id.uuidString) }

        #expect(studentLessons.count == 2)
    }

    @Test("Student can have attendance records")
    func canHaveAttendanceRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let date1 = TestCalendar.date(year: 2025, month: 1, day: 15)
        let date2 = TestCalendar.date(year: 2025, month: 1, day: 16)

        let record1 = makeTestAttendanceRecord(studentID: student.id, date: date1, status: .present)
        let record2 = makeTestAttendanceRecord(studentID: student.id, date: date2, status: .absent)
        context.insert(record1)
        context.insert(record2)
        try context.save()

        let descriptor = FetchDescriptor<AttendanceRecord>()
        let allRecords = try context.fetch(descriptor)
        let studentRecords = allRecords.filter { $0.studentID == student.id.uuidString }

        #expect(studentRecords.count == 2)
    }

    @Test("Student can have work assignments as participant")
    func canHaveWorkAssignments() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let work = WorkModel(title: "Practice Work", kind: .practiceLesson)
        let participant = WorkParticipantEntity(studentID: student.id, completedAt: nil, work: work)
        work.participants = [participant]
        context.insert(work)
        try context.save()

        #expect(work.participants?.count == 1)
        #expect(work.participants?[0].studentID == student.id.uuidString)
    }
}

// MARK: - Student nextLessons Tests

@Suite("Student nextLessons Tests", .serialized)
@MainActor
struct StudentNextLessonsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
        ])
    }

    @Test("nextLessons starts empty")
    func nextLessonsStartsEmpty() {
        let student = makeTestStudent()

        #expect(student.nextLessons.isEmpty)
    }

    @Test("nextLessonUUIDs converts strings to UUIDs")
    func nextLessonUUIDsConvertsCorrectly() {
        let student = makeTestStudent()
        let lessonID1 = UUID()
        let lessonID2 = UUID()

        student.nextLessonUUIDs = [lessonID1, lessonID2]

        #expect(student.nextLessonUUIDs.count == 2)
        #expect(student.nextLessonUUIDs.contains(lessonID1))
        #expect(student.nextLessonUUIDs.contains(lessonID2))
    }

    @Test("nextLessons stores as strings for CloudKit compatibility")
    func nextLessonsStoresAsStrings() {
        let student = makeTestStudent()
        let lessonID = UUID()

        student.nextLessonUUIDs = [lessonID]

        #expect(student.nextLessons.count == 1)
        #expect(student.nextLessons[0] == lessonID.uuidString)
    }
}

// MARK: - Student Persistence Tests

@Suite("Student Persistence Tests", .serialized)
@MainActor
struct StudentPersistenceTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Document.self,
        ])
    }

    @Test("Student round-trips through persistence")
    func roundTripsThroughPersistence() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let birthday = TestCalendar.date(year: 2015, month: 6, day: 15)
        let dateStarted = TestCalendar.date(year: 2023, month: 9, day: 1)

        let original = Student(
            firstName: "Alice",
            lastName: "Anderson",
            birthday: birthday,
            nickname: "Ali",
            level: .upper,
            dateStarted: dateStarted,
            manualOrder: 5
        )
        let originalID = original.id

        context.insert(original)
        try context.save()

        // Fetch back (filter to avoid UUID predicate issues)
        let descriptor = FetchDescriptor<Student>()
        let fetched = try context.fetch(descriptor).first { $0.id == originalID }

        #expect(fetched != nil)
        #expect(fetched?.id == originalID)
        #expect(fetched?.firstName == "Alice")
        #expect(fetched?.lastName == "Anderson")
        #expect(fetched?.birthday == birthday)
        #expect(fetched?.nickname == "Ali")
        #expect(fetched?.level == .upper)
        #expect(fetched?.dateStarted == dateStarted)
        #expect(fetched?.manualOrder == 5)
    }

    @Test("Student can be updated after fetch")
    func canBeUpdatedAfterFetch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)
        try context.save()

        // Update
        student.firstName = "Alicia"
        student.level = .upper
        try context.save()

        // Fetch back (filter to avoid UUID predicate issues)
        let descriptor = FetchDescriptor<Student>()
        let fetched = try context.fetch(descriptor).first { $0.id == student.id }

        #expect(fetched?.firstName == "Alicia")
        #expect(fetched?.level == .upper)
    }

    @Test("Student can be deleted")
    func canBeDeleted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let studentID = student.id
        context.insert(student)
        try context.save()

        context.delete(student)
        try context.save()

        // Fetch and filter to check deletion
        let descriptor = FetchDescriptor<Student>()
        let fetched = try context.fetch(descriptor).filter { $0.id == studentID }

        #expect(fetched.isEmpty)
    }
}

#endif
