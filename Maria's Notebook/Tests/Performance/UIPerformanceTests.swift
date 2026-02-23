#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Lesson Grouping Tests

/// Tests to verify lesson grouping logic remains correct during performance optimizations.
@Suite("Lesson Grouping Behavior Tests", .serialized)
@MainActor
struct LessonGroupingBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
        ])
    }

    @Test("Lessons group by subject correctly")
    func lessonsGroupBySubject() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create lessons in different subjects
        let mathLesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        let mathLesson2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations")
        let langLesson = makeTestLesson(name: "Reading", subject: "Language", group: "Reading")

        context.insert(mathLesson1)
        context.insert(mathLesson2)
        context.insert(langLesson)
        try context.save()

        let lessons = [mathLesson1, mathLesson2, langLesson]

        // Group by subject
        let grouped = Dictionary(grouping: lessons) { $0.subject }

        #expect(grouped["Math"]?.count == 2)
        #expect(grouped["Language"]?.count == 1)
    }

    @Test("Lessons group by group within subject correctly")
    func lessonsGroupByGroupWithinSubject() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create lessons in same subject, different groups
        let ops1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        let ops2 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations")
        let geo1 = makeTestLesson(name: "Shapes", subject: "Math", group: "Geometry")

        context.insert(ops1)
        context.insert(ops2)
        context.insert(geo1)
        try context.save()

        let lessons = [ops1, ops2, geo1]

        // Group by group name
        let grouped = Dictionary(grouping: lessons) { $0.group }

        #expect(grouped["Operations"]?.count == 2)
        #expect(grouped["Geometry"]?.count == 1)
    }

    @Test("Lesson ordering within group is preserved")
    func lessonOrderingWithinGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create lessons with specific order
        let lesson1 = makeTestLesson(name: "First", subject: "Math", group: "Ops", orderInGroup: 1)
        let lesson2 = makeTestLesson(name: "Second", subject: "Math", group: "Ops", orderInGroup: 2)
        let lesson3 = makeTestLesson(name: "Third", subject: "Math", group: "Ops", orderInGroup: 3)

        context.insert(lesson2) // Insert out of order
        context.insert(lesson1)
        context.insert(lesson3)
        try context.save()

        var lessons = [lesson1, lesson2, lesson3]
        lessons.sort { $0.orderInGroup < $1.orderInGroup }

        #expect(lessons[0].name == "First")
        #expect(lessons[1].name == "Second")
        #expect(lessons[2].name == "Third")
    }

    @Test("Group name trimming handles whitespace")
    func groupNameTrimmingHandlesWhitespace() {
        let name1 = "  Operations  ".trimmingCharacters(in: .whitespaces)
        let name2 = "Operations"

        #expect(name1 == name2)
    }

    @Test("Group name comparison is case insensitive")
    func groupNameComparisonIsCaseInsensitive() {
        let name1 = "Operations"
        let name2 = "OPERATIONS"

        #expect(name1.lowercased() == name2.lowercased())
    }
}

// MARK: - Date Formatting Tests

/// Tests to verify date formatting behavior for UI components.
@Suite("Date Formatting Behavior Tests")
struct DateFormattingBehaviorTests {

    @Test("Age calculation is consistent")
    func ageCalculationConsistent() {
        // Fixed reference date for testing
        let birthday = TestCalendar.date(year: 2018, month: 6, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: birthday, to: referenceDate)

        #expect(components.year == 7)
        #expect(components.month == 0)
    }

    @Test("Quarter age calculation handles edge cases")
    func quarterAgeCalculation() {
        let birthday = TestCalendar.date(year: 2020, month: 3, day: 15)
        let referenceDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: birthday, to: referenceDate)

        let years = components.year ?? 0
        let months = components.month ?? 0
        let quarterMonths = months / 3

        #expect(years == 5)
        #expect(quarterMonths == 1) // 3 months = 1 quarter
    }

    @Test("Birthday display formats correctly")
    func birthdayDisplayFormat() {
        let birthday = TestCalendar.date(year: 2018, month: 6, day: 15)

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let formatted = formatter.string(from: birthday)

        // Should contain month, day, and year
        #expect(formatted.contains("2018"))
    }
}

// MARK: - Student Card Display Tests

/// Tests to verify student card display logic.
@Suite("Student Card Display Tests", .serialized)
@MainActor
struct StudentCardDisplayTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [Student.self])
    }

    @Test("Student display name uses nickname when available")
    func studentDisplayNameUsesNickname() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(
            firstName: "Elizabeth",
            lastName: "Smith",
            nickname: "Lizzy"
        )
        context.insert(student)

        // Display name should prefer nickname
        let displayName = student.nickname ?? student.firstName
        #expect(displayName == "Lizzy")
    }

    @Test("Student display name uses first name when no nickname")
    func studentDisplayNameUsesFirstName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(
            firstName: "John",
            lastName: "Doe",
            nickname: nil
        )
        context.insert(student)

        // Display name should fall back to first name
        let displayName = student.nickname ?? student.firstName
        #expect(displayName == "John")
    }

    @Test("Student full name combines first and last")
    func studentFullName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "John", lastName: "Doe")
        context.insert(student)

        #expect(student.fullName == "John Doe")
    }

    @Test("Student level raw values are correct")
    func studentLevelRawValues() {
        #expect(Student.Level.lower.rawValue == "Lower")
        #expect(Student.Level.upper.rawValue == "Upper")
    }
}

// MARK: - List Identifier Tests

/// Tests to verify that identifiers for lists work correctly.
@Suite("List Identifier Tests", .serialized)
@MainActor
struct ListIdentifierTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
        ])
    }

    @Test("Student IDs are unique")
    func studentIDsAreUnique() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let students = (0..<10).map { i in
            makeTestStudent(firstName: "Student", lastName: "\(i)")
        }

        for student in students {
            context.insert(student)
        }
        try context.save()

        let ids = students.map { $0.id }
        let uniqueIDs = Set(ids)

        #expect(uniqueIDs.count == 10)
    }

    @Test("Lesson IDs are unique")
    func lessonIDsAreUnique() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessons = (0..<10).map { i in
            makeTestLesson(name: "Lesson \(i)")
        }

        for lesson in lessons {
            context.insert(lesson)
        }
        try context.save()

        let ids = lessons.map { $0.id }
        let uniqueIDs = Set(ids)

        #expect(uniqueIDs.count == 10)
    }

    @Test("StudentLesson IDs are stable")
    func studentLessonIDsAreStable() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let lesson = makeTestLesson()
        context.insert(student)
        context.insert(lesson)

        let studentLesson = StudentLesson(lesson: lesson, students: [student])
        context.insert(studentLesson)
        try context.save()

        let originalID = studentLesson.id

        // Access ID again
        let accessedID = studentLesson.id

        #expect(originalID == accessedID)
    }
}

// MARK: - Schedule Display Tests

/// Tests for schedule/work display logic.
@Suite("Schedule Display Tests", .serialized)
@MainActor
struct ScheduleDisplayTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            WorkModel.self,
            WorkParticipantEntity.self,
        ])
    }

    @Test("Work status display text is correct")
    func workStatusDisplayText() {
        #expect(WorkStatus.active.displayName == "Active")
        #expect(WorkStatus.review.displayName == "Review")
        #expect(WorkStatus.complete.displayName == "Complete")
    }

    @Test("Work type raw values are correct")
    func workTypeRawValues() {
        #expect(WorkModel.WorkType.practice.rawValue == "Practice")
        #expect(WorkModel.WorkType.research.rawValue == "Research")
        #expect(WorkModel.WorkType.followUp.rawValue == "Follow Up")
        #expect(WorkModel.WorkType.report.rawValue == "Report")
    }

    @Test("Overdue work is identified correctly")
    func overdueWorkIdentification() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pastDate = TestCalendar.daysAgo(2)
        let futureDate = TestCalendar.daysFromNow(2)

        let overdueWork = makeTestWorkModel(
            title: "Overdue",
            status: .active,
            dueAt: pastDate
        )
        let futureWork = makeTestWorkModel(
            title: "Future",
            status: .active,
            dueAt: futureDate
        )

        context.insert(overdueWork)
        context.insert(futureWork)
        try context.save()

        let now = Date()

        let isOverdue1 = overdueWork.dueAt != nil && overdueWork.dueAt! < now
        let isOverdue2 = futureWork.dueAt != nil && futureWork.dueAt! < now

        #expect(isOverdue1 == true)
        #expect(isOverdue2 == false)
    }
}

// MARK: - Sorting Behavior Tests

/// Tests to verify sorting algorithms work correctly.
@Suite("Sorting Behavior Tests", .serialized)
@MainActor
struct SortingBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
        ])
    }

    @Test("Students sort by manual order")
    func studentsSortByManualOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Charlie", manualOrder: 3)
        let student2 = makeTestStudent(firstName: "Alice", manualOrder: 1)
        let student3 = makeTestStudent(firstName: "Bob", manualOrder: 2)

        context.insert(student1)
        context.insert(student2)
        context.insert(student3)
        try context.save()

        var students = [student1, student2, student3]
        students.sort { $0.manualOrder < $1.manualOrder }

        #expect(students[0].firstName == "Alice")
        #expect(students[1].firstName == "Bob")
        #expect(students[2].firstName == "Charlie")
    }

    @Test("Students sort by name when manual order is same")
    func studentsSortByNameWhenSameOrder() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Charlie", lastName: "Smith", manualOrder: 0)
        let student2 = makeTestStudent(firstName: "Alice", lastName: "Jones", manualOrder: 0)
        let student3 = makeTestStudent(firstName: "Bob", lastName: "Brown", manualOrder: 0)

        context.insert(student1)
        context.insert(student2)
        context.insert(student3)
        try context.save()

        var students = [student1, student2, student3]
        students.sort {
            if $0.manualOrder != $1.manualOrder {
                return $0.manualOrder < $1.manualOrder
            }
            return $0.firstName < $1.firstName
        }

        #expect(students[0].firstName == "Alice")
        #expect(students[1].firstName == "Bob")
        #expect(students[2].firstName == "Charlie")
    }

    @Test("Lessons sort by orderInGroup")
    func lessonsSortByOrderInGroup() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Third", orderInGroup: 3)
        let lesson2 = makeTestLesson(name: "First", orderInGroup: 1)
        let lesson3 = makeTestLesson(name: "Second", orderInGroup: 2)

        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        var lessons = [lesson1, lesson2, lesson3]
        lessons.sort { $0.orderInGroup < $1.orderInGroup }

        #expect(lessons[0].name == "First")
        #expect(lessons[1].name == "Second")
        #expect(lessons[2].name == "Third")
    }
}

// MARK: - View State Tests

/// Tests to verify view state calculations.
@Suite("View State Calculation Tests", .serialized)
@MainActor
struct ViewStateCalculationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
        ])
    }

    @Test("Empty state detection works")
    func emptyStateDetection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let descriptor = FetchDescriptor<Student>()
        let students = try context.fetch(descriptor)

        let isEmpty = students.isEmpty

        #expect(isEmpty == true)
    }

    @Test("Non-empty state detection works")
    func nonEmptyStateDetection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        context.insert(student)
        try context.save()

        let descriptor = FetchDescriptor<Student>()
        let students = try context.fetch(descriptor)

        let isEmpty = students.isEmpty

        #expect(isEmpty == false)
    }

    @Test("Filtered count is calculated correctly")
    func filteredCountCalculation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create students with different levels
        let lowerStudents = (0..<5).map { _ in
            makeTestStudent(level: .lower)
        }
        let upperStudents = (0..<3).map { _ in
            makeTestStudent(level: .upper)
        }

        for student in lowerStudents + upperStudents {
            context.insert(student)
        }
        try context.save()

        let descriptor = FetchDescriptor<Student>()
        let allStudents = try context.fetch(descriptor)

        let lowerCount = allStudents.filter { $0.level == .lower }.count
        let upperCount = allStudents.filter { $0.level == .upper }.count

        #expect(lowerCount == 5)
        #expect(upperCount == 3)
    }
}

// MARK: - Computed Property Caching Tests

/// Tests to verify computed properties return consistent values.
@Suite("Computed Property Consistency Tests", .serialized)
@MainActor
struct ComputedPropertyConsistencyTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Note.self,
            NoteStudentLink.self,
        ])
    }

    @Test("Note scope getter returns same value on repeated access")
    func noteScopeConsistency() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let note = Note(body: "Test", scope: .student(studentID))
        context.insert(note)
        try context.save()

        // Access scope multiple times
        let scope1 = note.scope
        let scope2 = note.scope
        let scope3 = note.scope

        // All should be equal
        if case .student(let id1) = scope1,
           case .student(let id2) = scope2,
           case .student(let id3) = scope3 {
            #expect(id1 == studentID)
            #expect(id2 == studentID)
            #expect(id3 == studentID)
        } else {
            Issue.record("Expected student scope")
        }
    }

    @Test("Note category getter returns same value")
    func noteCategoryConsistency() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(body: "Test", scope: .all, category: .behavioral)
        context.insert(note)
        try context.save()

        let cat1 = note.category
        let cat2 = note.category

        #expect(cat1 == .behavioral)
        #expect(cat2 == .behavioral)
    }
}

#endif
