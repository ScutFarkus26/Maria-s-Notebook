#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Presented Student Lessons Tests

@Suite("InboxDataLoader Presented StudentLessons Tests", .serialized)
@MainActor
struct InboxDataLoaderPresentedStudentLessonsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("loadPresentedStudentLessons returns lessons with isPresented true")
    func loadPresentedStudentLessonsReturnsPresented() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let presented = makeTestStudentLesson(isPresented: true)
        let notPresented = makeTestStudentLesson(isPresented: false)
        context.insert(presented)
        context.insert(notPresented)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let lessons = loader.loadPresentedStudentLessons()

        #expect(lessons.count == 1)
        #expect(lessons[0].isPresented == true)
    }

    @Test("loadPresentedStudentLessons includes lessons with givenAt")
    func loadPresentedStudentLessonsIncludesGivenAt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let withGivenAt = makeTestStudentLesson(givenAt: Date(), isPresented: false)
        let notPresented = makeTestStudentLesson(isPresented: false)
        context.insert(withGivenAt)
        context.insert(notPresented)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let lessons = loader.loadPresentedStudentLessons()

        #expect(lessons.count == 1)
        #expect(lessons[0].givenAt != nil)
    }

    @Test("loadPresentedStudentLessons combines isPresented and givenAt without duplicates")
    func loadPresentedStudentLessonsNoDuplicates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Lesson that has both isPresented=true AND givenAt set
        let bothSet = makeTestStudentLesson(givenAt: Date(), isPresented: true)
        context.insert(bothSet)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let lessons = loader.loadPresentedStudentLessons()

        #expect(lessons.count == 1)
    }

    @Test("loadPresentedStudentLessons returns empty for no presented lessons")
    func loadPresentedStudentLessonsReturnsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let notPresented = makeTestStudentLesson(isPresented: false)
        context.insert(notPresented)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let lessons = loader.loadPresentedStudentLessons()

        #expect(lessons.isEmpty)
    }
}

// MARK: - Active Work Models Tests

@Suite("InboxDataLoader Active WorkModels Tests", .serialized)
@MainActor
struct InboxDataLoaderActiveWorkModelsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("loadActiveWorkModels returns active work")
    func loadActiveWorkModelsReturnsActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let active = makeTestWorkModel(status: .active)
        let completed = makeTestWorkModel(status: .complete)
        context.insert(active)
        context.insert(completed)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let works = loader.loadActiveWorkModels()

        #expect(works.count == 1)
        #expect(works[0].status == .active)
    }

    @Test("loadActiveWorkModels returns review work")
    func loadActiveWorkModelsReturnsReview() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let review = makeTestWorkModel(status: .review)
        let completed = makeTestWorkModel(status: .complete)
        context.insert(review)
        context.insert(completed)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let works = loader.loadActiveWorkModels()

        #expect(works.count == 1)
        #expect(works[0].status == .review)
    }

    @Test("loadActiveWorkModels excludes completed work")
    func loadActiveWorkModelsExcludesCompleted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let completed = makeTestWorkModel(status: .complete)
        context.insert(completed)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let works = loader.loadActiveWorkModels()

        #expect(works.isEmpty)
    }

    @Test("loadActiveWorkModels returns both active and review")
    func loadActiveWorkModelsReturnsBoth() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let active = makeTestWorkModel(status: .active)
        let review = makeTestWorkModel(status: .review)
        context.insert(active)
        context.insert(review)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let works = loader.loadActiveWorkModels()

        #expect(works.count == 2)
        let statuses = Set(works.map { $0.status })
        #expect(statuses.contains(.active))
        #expect(statuses.contains(.review))
    }
}

// MARK: - Plan Items Tests

@Suite("InboxDataLoader Plan Items Tests", .serialized)
@MainActor
struct InboxDataLoaderPlanItemsTests {

    private func makeContainer() throws -> ModelContainer {
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
        ])
    }

    @Test("loadPlanItems returns items for specified work IDs")
    func loadPlanItemsReturnsForWorkIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work1 = makeTestWorkModel()
        let work2 = makeTestWorkModel()
        context.insert(work1)
        context.insert(work2)

        let item1 = WorkPlanItem(workID: work1.id.uuidString, text: "Item 1")
        let item2 = WorkPlanItem(workID: work2.id.uuidString, text: "Item 2")
        context.insert(item1)
        context.insert(item2)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let items = loader.loadPlanItems(for: Set([work1.id]))

        #expect(items.count == 1)
        #expect(items[0].text == "Item 1")
    }

    @Test("loadPlanItems returns empty for empty work IDs")
    func loadPlanItemsReturnsEmptyForEmptyWorkIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loader = InboxDataLoader(context: context)
        let items = loader.loadPlanItems(for: Set<UUID>())

        #expect(items.isEmpty)
    }

    @Test("loadPlanItems returns multiple items for same work")
    func loadPlanItemsReturnsMultipleForSameWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = makeTestWorkModel()
        context.insert(work)

        let item1 = WorkPlanItem(workID: work.id.uuidString, text: "Item 1")
        let item2 = WorkPlanItem(workID: work.id.uuidString, text: "Item 2")
        context.insert(item1)
        context.insert(item2)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let items = loader.loadPlanItems(for: Set([work.id]))

        #expect(items.count == 2)
    }
}

// MARK: - Load Students Tests

@Suite("InboxDataLoader Students Tests", .serialized)
@MainActor
struct InboxDataLoaderStudentsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("loadStudents returns students for specified IDs")
    func loadStudentsReturnsForIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Smith")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Jones")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let students = loader.loadStudents(ids: Set([student1.id, student3.id]))

        #expect(students.count == 2)
        let names = Set(students.map { $0.firstName })
        #expect(names.contains("Alice"))
        #expect(names.contains("Charlie"))
    }

    @Test("loadStudents returns empty for empty IDs")
    func loadStudentsReturnsEmptyForEmptyIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loader = InboxDataLoader(context: context)
        let students = loader.loadStudents(ids: Set<UUID>())

        #expect(students.isEmpty)
    }
}

// MARK: - Load Lessons Tests

@Suite("InboxDataLoader Lessons Tests", .serialized)
@MainActor
struct InboxDataLoaderLessonsTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("loadLessons returns lessons for specified IDs")
    func loadLessonsReturnsForIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson1 = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        let lesson2 = makeTestLesson(name: "Reading", subject: "Language", group: "Literacy")
        let lesson3 = makeTestLesson(name: "Subtraction", subject: "Math", group: "Operations")
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)
        try context.save()

        let loader = InboxDataLoader(context: context)
        let lessons = loader.loadLessons(ids: Set([lesson1.id, lesson3.id]))

        #expect(lessons.count == 2)
        let names = Set(lessons.map { $0.name })
        #expect(names.contains("Addition"))
        #expect(names.contains("Subtraction"))
    }

    @Test("loadLessons returns empty for empty IDs")
    func loadLessonsReturnsEmptyForEmptyIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loader = InboxDataLoader(context: context)
        let lessons = loader.loadLessons(ids: Set<UUID>())

        #expect(lessons.isEmpty)
    }
}

// MARK: - Load Inbox Data Integration Tests

@Suite("InboxDataLoader Integration Tests", .serialized)
@MainActor
struct InboxDataLoaderIntegrationTests {

    private func makeContainer() throws -> ModelContainer {
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
        ])
    }

    @Test("loadInboxData returns complete data structure")
    func loadInboxDataReturnsCompleteStructure() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create students
        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(student)

        // Create lessons
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        // Create presented student lesson
        let studentLesson = makeTestStudentLesson(
            lessonID: lesson.id,
            studentIDs: [student.id],
            isPresented: true
        )
        context.insert(studentLesson)

        // Create active work
        let work = makeTestWorkModel(
            status: .active,
            studentID: student.id.uuidString,
            lessonID: lesson.id.uuidString
        )
        context.insert(work)

        // Create plan item for work
        let planItem = WorkPlanItem(workID: work.id.uuidString, text: "Practice problems")
        context.insert(planItem)

        try context.save()

        let loader = InboxDataLoader(context: context)
        let inboxData = loader.loadInboxData()

        #expect(inboxData.studentLessons.count >= 1)
        #expect(!inboxData.students.isEmpty)
        #expect(!inboxData.lessons.isEmpty)
    }

    @Test("loadInboxData handles empty database")
    func loadInboxDataHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let loader = InboxDataLoader(context: context)
        let inboxData = loader.loadInboxData()

        #expect(inboxData.studentLessons.isEmpty)
        #expect(inboxData.planItems.isEmpty)
        #expect(inboxData.notes.isEmpty)
        #expect(inboxData.students.isEmpty)
        #expect(inboxData.lessons.isEmpty)
    }
}

#endif
