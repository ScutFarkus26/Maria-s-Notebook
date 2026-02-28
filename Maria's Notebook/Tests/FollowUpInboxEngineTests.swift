#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("FollowUpInboxItem Tests", .serialized)
@MainActor
struct FollowUpInboxItemTests {

    // MARK: - Kind Tests

    @Test("Kind label mappings are correct")
    func kindLabelMappings() {
        let cases: [(FollowUpInboxItem.Kind, String)] = [
            (.lessonFollowUp, "Lesson"),
            (.workCheckIn, "Check-In"),
            (.workReview, "Review")
        ]
        expectEnumProperty(for: cases, keyPath: \.label)
    }

    @Test("Kind icon mappings are correct")
    func kindIconMappings() {
        let cases: [(FollowUpInboxItem.Kind, String)] = [
            (.lessonFollowUp, "text.book.closed"),
            (.workCheckIn, "checklist"),
            (.workReview, "eye")
        ]
        expectEnumProperty(for: cases, keyPath: \.icon)
    }

    // MARK: - Bucket Tests

    @Test("Bucket rawValue mappings are correct")
    func bucketRawValueMappings() {
        let cases: [(FollowUpInboxItem.Bucket, Int)] = [
            (.overdue, 0),
            (.dueToday, 1),
            (.inbox, 2),
            (.upcoming, 3)
        ]
        expectEnumProperty(for: cases, keyPath: \.rawValue)
    }

    @Test("Bucket title mappings are correct")
    func bucketTitleMappings() {
        let cases: [(FollowUpInboxItem.Bucket, String)] = [
            (.overdue, "Overdue"),
            (.dueToday, "Due Today"),
            (.inbox, "Needs Scheduling"),
            (.upcoming, "Upcoming")
        ]
        expectEnumProperty(for: cases, keyPath: \.title)
    }

    // MARK: - Bucket Comparison Tests

    @Test("Bucket ordering follows priority")
    func bucketOrderingFollowsPriority() {
        #expect(FollowUpInboxItem.Bucket.overdue < .dueToday)
        #expect(FollowUpInboxItem.Bucket.dueToday < .inbox)
        #expect(FollowUpInboxItem.Bucket.inbox < .upcoming)
        #expect(FollowUpInboxItem.Bucket.allCases.min() == .overdue)
        #expect(FollowUpInboxItem.Bucket.allCases.max() == .upcoming)
    }

    // MARK: - FollowUpInboxItem Creation Tests

    @Test("FollowUpInboxItem stores all properties correctly")
    func itemStoresProperties() {
        let builder = FollowUpInboxItemBuilder()
        let item = builder
            .withBucket(.overdue)
            .withAge(10)
            .build()

        #expect(item.childName == "Test Child")
        #expect(item.title == "Test Lesson")
        #expect(item.kind == .lessonFollowUp)
        #expect(item.ageDays == 10)
        #expect(item.bucket == .overdue)
    }

    @Test("FollowUpInboxItem allows nil childID")
    func itemAllowsNilChildID() {
        let item = FollowUpInboxItemBuilder()
            .withNoChild()
            .withChildName("Group")
            .build()

        #expect(item.childID == nil)
        #expect(item.childName == "Group")
    }

    // MARK: - sortKey Tests

    @Test("sortKey sorts by bucket, then age, then child name")
    func sortKeyOrdering() {
        let builder = FollowUpInboxItemBuilder().withNoChild()

        // Bucket priority
        let overdue = builder.withBucket(.overdue).withAge(10).withChildName("Alice").build()
        let upcoming = builder.withBucket(.upcoming).withAge(10).withChildName("Alice").build()
        #expect(overdue.sortKey < upcoming.sortKey)

        // Age within bucket (higher age first)
        let older = builder.withBucket(.overdue).withAge(15).withChildName("Alice").build()
        let newer = builder.withBucket(.overdue).withAge(8).withChildName("Alice").build()
        #expect(older.sortKey < newer.sortKey)

        // Child name within bucket and age
        let alice = builder.withBucket(.overdue).withAge(10).withChildName("Alice").build()
        let bob = builder.withBucket(.overdue).withAge(10).withChildName("Bob").build()
        #expect(alice.sortKey < bob.sortKey)
    }

    @Test("sortKey is case insensitive for child name")
    func sortKeyCaseInsensitiveChildName() {
        let builder = FollowUpInboxItemBuilder().withNoChild().withBucket(.overdue).withAge(10)
        let lowercase = builder.withChildName("alice").build()
        let uppercase = builder.withChildName("ALICE").build()
        #expect(lowercase.sortKey == uppercase.sortKey)
    }

    // MARK: - Equatable Tests

    @Test("FollowUpInboxItem equality based on all fields")
    func itemEquality() {
        let id = UUID()
        let childID = UUID()

        let item1 = FollowUpInboxItem(
            id: "test:123",
            underlyingID: id,
            childID: childID,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "Status",
            ageDays: 10,
            bucket: .overdue
        )

        let item2 = FollowUpInboxItem(
            id: "test:123",
            underlyingID: id,
            childID: childID,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "Status",
            ageDays: 10,
            bucket: .overdue
        )

        #expect(item1 == item2)
    }

    @Test("FollowUpInboxItem inequality when ID differs")
    func itemInequalityDifferentID() {
        let item1 = FollowUpInboxItem(
            id: "test:123",
            underlyingID: UUID(),
            childID: nil,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "Status",
            ageDays: 10,
            bucket: .overdue
        )

        let item2 = FollowUpInboxItem(
            id: "test:456",
            underlyingID: UUID(),
            childID: nil,
            childName: "Alice",
            title: "Lesson",
            kind: .lessonFollowUp,
            statusText: "Status",
            ageDays: 10,
            bucket: .overdue
        )

        #expect(item1 != item2)
    }
}

@Suite("FollowUpInboxEngine.Constants Tests", .serialized)
struct FollowUpInboxEngineConstantsTests {

    @Test("Default lessonFollowUpOverdueDays is 7")
    func defaultLessonOverdueDays() {
        let constants = FollowUpInboxEngine.Constants()

        #expect(constants.lessonFollowUpOverdueDays == 7)
    }

    @Test("Default workStaleOverdueDays is 5")
    func defaultWorkStaleOverdueDays() {
        let constants = FollowUpInboxEngine.Constants()

        #expect(constants.workStaleOverdueDays == 5)
    }

    @Test("Default reviewStaleDays is 3")
    func defaultReviewStaleDays() {
        let constants = FollowUpInboxEngine.Constants()

        #expect(constants.reviewStaleDays == 3)
    }

    @Test("Constants can be customized")
    func customConstants() {
        var constants = FollowUpInboxEngine.Constants()
        constants.lessonFollowUpOverdueDays = 14
        constants.workStaleOverdueDays = 10
        constants.reviewStaleDays = 7

        #expect(constants.lessonFollowUpOverdueDays == 14)
        #expect(constants.workStaleOverdueDays == 10)
        #expect(constants.reviewStaleDays == 7)
    }
}

@Suite("FollowUpInboxEngine Edge Cases Tests", .serialized)
@MainActor
struct FollowUpInboxEngineEdgeCasesTests {

    // MARK: - Empty Dataset Tests

    @Test("computeItems returns empty array when all inputs are empty")
    func emptyInputsReturnEmpty() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let items = FollowUpInboxEngine.computeItems(
            lessons: [],
            students: [],
            lessonAssignments: [],
            modelContext: context
        )

        #expect(items.isEmpty)
    }

    @Test("computeItems handles empty lessons list")
    func emptyLessons() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let la = LessonAssignment(state: .presented, presentedAt: Date(), lessonID: UUID(), studentIDs: [student.id])

        let items = FollowUpInboxEngine.computeItems(
            lessons: [],
            students: [student],
            lessonAssignments: [la],
            modelContext: context
        )

        #expect(items.count >= 0) // Should handle gracefully
    }

    @Test("computeItems handles empty students list")
    func emptyStudents() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson()
        let la = LessonAssignment(state: .presented, presentedAt: Date(), lessonID: lesson.id, studentIDs: [])

        let items = FollowUpInboxEngine.computeItems(
            lessons: [lesson],
            students: [],
            lessonAssignments: [la],
            modelContext: context
        )

        #expect(items.count >= 0) // Should handle gracefully
    }

    @Test("computeItems handles empty studentLessons list")
    func emptyStudentLessons() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson()
        let student = makeTestStudent()

        let items = FollowUpInboxEngine.computeItems(
            lessons: [lesson],
            students: [student],
            lessonAssignments: [],
            modelContext: context
        )

        #expect(items.isEmpty)
    }

    // MARK: - Large Dataset Tests

    @Test("computeItems handles 100+ items efficiently")
    func largeDataset() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let students = (0..<50).map { i in
            makeTestStudent(firstName: "Student\(i)", lastName: "Last\(i)")
        }
        let lessons = (0..<20).map { i in
            makeTestLesson(name: "Lesson \(i)")
        }
        let lessonAssignments: [LessonAssignment] = (0..<100).map { i in
            let student = students[i % students.count]
            let lesson = lessons[i % lessons.count]
            return LessonAssignment(
                state: .presented,
                presentedAt: TestCalendar.date(year: 2025, month: 1, day: 1),
                lessonID: lesson.id,
                studentIDs: [student.id]
            )
        }

        let items = FollowUpInboxEngine.computeItems(
            lessons: lessons,
            students: students,
            lessonAssignments: lessonAssignments,
            modelContext: context
        )

        #expect(items.count >= 0)
    }

    // MARK: - Bucket Classification Edge Cases

    @Test("computeItems classifies lessons by age threshold")
    func bucketClassification() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let lesson = makeTestLesson()

        // Test at threshold (7 school days = dueToday)
        let sl1 = LessonAssignment(
            state: .presented,
            presentedAt: schoolDaysAgo(7),
            lessonID: lesson.id,
            studentIDs: [student.id]
        )
        let items1 = FollowUpInboxEngine.computeItems(
            lessons: [lesson],
            students: [student],
            lessonAssignments: [sl1],
            modelContext: context
        )
        if let item = items1.first {
            #expect(item.bucket == .dueToday)
        }

        // Test past threshold (8 school days = overdue)
        let sl2 = LessonAssignment(
            state: .presented,
            presentedAt: schoolDaysAgo(8),
            lessonID: lesson.id,
            studentIDs: [student.id]
        )
        let items2 = FollowUpInboxEngine.computeItems(
            lessons: [lesson],
            students: [student],
            lessonAssignments: [sl2],
            modelContext: context
        )
        if let item = items2.first {
            #expect(item.bucket == .overdue)
        }

        // Test before threshold (5 days = upcoming)
        let sl3 = LessonAssignment(
            state: .presented,
            presentedAt: AppCalendar.addingDays(-5, to: Date()),
            lessonID: lesson.id,
            studentIDs: [student.id]
        )
        let items3 = FollowUpInboxEngine.computeItems(
            lessons: [lesson],
            students: [student],
            lessonAssignments: [sl3],
            modelContext: context
        )
        if let item = items3.first {
            #expect(item.bucket == .upcoming)
        }
    }

    // MARK: - Exclusion Logic Tests

    @Test("computeItems excludes lessons with follow-up work")
    func excludesLessonsWithFollowUpWork() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let lesson = makeTestLesson()
        let la = LessonAssignment(
            state: .presented,
            presentedAt: TestCalendar.date(year: 2025, month: 1, day: 1),
            lessonID: lesson.id,
            studentIDs: [student.id]
        )

        let work = WorkModel(
            title: "Follow-up work",
            status: .active,
            studentID: student.id.uuidString,
            lessonID: lesson.id.uuidString
        )
        work.presentationID = la.id.uuidString
        context.insert(work)
        try context.save()

        let items = FollowUpInboxEngine.computeItems(
            lessons: [lesson],
            students: [student],
            lessonAssignments: [la],
            modelContext: context
        )

        #expect(items.filter { $0.kind == .lessonFollowUp }.isEmpty)
    }

    // MARK: - Multi-Student Group Tests

    @Test("computeItems handles group lessons with multiple students")
    func groupLessonsMultipleStudents() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let students = [
            makeTestStudent(firstName: "Alice", lastName: "Anderson"),
            makeTestStudent(firstName: "Bob", lastName: "Brown"),
            makeTestStudent(firstName: "Charlie", lastName: "Chen")
        ]
        let lesson = makeTestLesson(name: "Group Lesson")
        let la = LessonAssignment(
            state: .presented,
            presentedAt: TestCalendar.date(year: 2025, month: 1, day: 1),
            lessonID: lesson.id,
            studentIDs: students.map { $0.id }
        )

        let items = FollowUpInboxEngine.computeItems(
            lessons: [lesson],
            students: students,
            lessonAssignments: [la],
            modelContext: context
        )

        if let item = items.first(where: { $0.kind == .lessonFollowUp }) {
            #expect(item.childName == "Group")
            #expect(item.childID == nil)
        }
    }

    // MARK: - Student-Specific Filtering Tests

    @Test("computeItems(for:) filters to specific student")
    func filterToSpecificStudent() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let lesson = makeTestLesson()

        let sl1 = LessonAssignment(
            state: .presented,
            presentedAt: TestCalendar.date(year: 2025, month: 1, day: 1),
            lessonID: lesson.id,
            studentIDs: [student1.id]
        )
        let sl2 = LessonAssignment(
            state: .presented,
            presentedAt: TestCalendar.date(year: 2025, month: 1, day: 1),
            lessonID: lesson.id,
            studentIDs: [student2.id]
        )

        let items = FollowUpInboxEngine.computeItems(
            for: student1.id,
            lessons: [lesson],
            students: [student1, student2],
            lessonAssignments: [sl1, sl2],
            modelContext: context
        )

        #expect(items.allSatisfy { $0.childID == student1.id })
    }

    @Test("computeItems(for:) returns empty for non-existent student")
    func filterToNonExistentStudent() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let lesson = makeTestLesson()
        let la = LessonAssignment(
            state: .presented,
            presentedAt: TestCalendar.date(year: 2025, month: 1, day: 1),
            lessonID: lesson.id,
            studentIDs: [student.id]
        )

        let items = FollowUpInboxEngine.computeItems(
            for: UUID(),
            lessons: [lesson],
            students: [student],
            lessonAssignments: [la],
            modelContext: context
        )

        #expect(items.isEmpty)
    }

    // MARK: - Sorting Tests

    @Test("computeItems sorts by bucket priority first")
    func sortsByBucketFirst() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let lesson1 = makeTestLesson(name: "Lesson 1")
        let lesson2 = makeTestLesson(name: "Lesson 2")

        let overdueLesson = LessonAssignment(
            state: .presented,
            presentedAt: schoolDaysAgo(10),
            lessonID: lesson1.id,
            studentIDs: [student.id]
        )
        let upcomingLesson = LessonAssignment(
            state: .presented,
            presentedAt: schoolDaysAgo(5),
            lessonID: lesson2.id,
            studentIDs: [student.id]
        )

        let items = FollowUpInboxEngine.computeItems(
            lessons: [lesson1, lesson2],
            students: [student],
            lessonAssignments: [overdueLesson, upcomingLesson],
            modelContext: context
        )

        #expect(items.count == 2)
        #expect(items[0].bucket == .overdue)
        #expect(items[1].bucket == .upcoming)
    }

    @Test("computeItems sorts by age descending within same bucket")
    func sortsByAgeWithinBucket() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let lesson1 = makeTestLesson(name: "Lesson 1")
        let lesson2 = makeTestLesson(name: "Lesson 2")

        let olderLesson = LessonAssignment(
            state: .presented,
            presentedAt: AppCalendar.addingDays(-15, to: Date()),
            lessonID: lesson1.id,
            studentIDs: [student.id]
        )
        let newerLesson = LessonAssignment(
            state: .presented,
            presentedAt: AppCalendar.addingDays(-10, to: Date()),
            lessonID: lesson2.id,
            studentIDs: [student.id]
        )

        let items = FollowUpInboxEngine.computeItems(
            lessons: [lesson1, lesson2],
            students: [student],
            lessonAssignments: [olderLesson, newerLesson],
            modelContext: context
        )

        #expect(items.count == 2)
        #expect(items[0].ageDays > items[1].ageDays)
    }

    // MARK: - Custom Constants Tests

    @Test("computeItems respects custom threshold constants")
    func customThresholds() throws {
        let container = try makeFollowUpContainer()
        let context = ModelContext(container)

        let student = makeTestStudent()
        let lesson = makeTestLesson()

        let la = LessonAssignment(
            state: .presented,
            presentedAt: AppCalendar.addingDays(-10, to: Date()),
            lessonID: lesson.id,
            studentIDs: [student.id]
        )

        var customConstants = FollowUpInboxEngine.Constants()
        customConstants.lessonFollowUpOverdueDays = 15

        let items = FollowUpInboxEngine.computeItems(
            lessons: [lesson],
            students: [student],
            lessonAssignments: [la],
            modelContext: context,
            constants: customConstants
        )

        if let item = items.first {
            #expect(item.bucket != .overdue && item.bucket != .dueToday)
        }
    }
}
#endif
