#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Fetch Tests

@Suite("StudentLessonRepository Fetch Tests", .serialized)
@MainActor
struct StudentLessonRepositoryFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("fetchStudentLesson returns by ID")
    func fetchStudentLessonReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let studentID = UUID()
        let sl = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID])
        context.insert(sl)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let fetched = repository.fetchStudentLesson(id: sl.id)

        #expect(fetched != nil)
        #expect(fetched?.id == sl.id)
    }

    @Test("fetchStudentLesson returns nil for missing ID")
    func fetchStudentLessonReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = StudentLessonRepository(context: context)
        let fetched = repository.fetchStudentLesson(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchStudentLessons returns all when no predicate")
    func fetchStudentLessonsReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl1 = makeTestStudentLesson()
        let sl2 = makeTestStudentLesson()
        let sl3 = makeTestStudentLesson()
        context.insert(sl1)
        context.insert(sl2)
        context.insert(sl3)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let fetched = repository.fetchStudentLessons()

        #expect(fetched.count == 3)
    }

    @Test("fetchStudentLessons forLessonID filters correctly")
    func fetchStudentLessonsForLessonIDFilters() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID1 = UUID()
        let lessonID2 = UUID()

        let sl1 = makeTestStudentLesson(lessonID: lessonID1)
        let sl2 = makeTestStudentLesson(lessonID: lessonID1)
        let sl3 = makeTestStudentLesson(lessonID: lessonID2)
        context.insert(sl1)
        context.insert(sl2)
        context.insert(sl3)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let fetched = repository.fetchStudentLessons(forLessonID: lessonID1)

        #expect(fetched.count == 2)
        #expect(fetched.allSatisfy { $0.lessonID == lessonID1.uuidString })
    }

    @Test("fetchInboxItems returns unscheduled items")
    func fetchInboxItemsReturnsUnscheduled() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl1 = makeTestStudentLesson(scheduledFor: nil, givenAt: nil, isPresented: false)
        let sl2 = makeTestStudentLesson(scheduledFor: Date(), givenAt: nil, isPresented: false)
        let sl3 = makeTestStudentLesson(scheduledFor: nil, givenAt: Date(), isPresented: true)
        context.insert(sl1)
        context.insert(sl2)
        context.insert(sl3)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let fetched = repository.fetchInboxItems()

        #expect(fetched.count == 1)
        #expect(fetched[0].scheduledFor == nil)
        #expect(fetched[0].givenAt == nil)
    }

    @Test("fetchScheduled returns items in date range")
    func fetchScheduledReturnsItemsInRange() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let startDate = TestCalendar.startOfDay(year: 2025, month: 1, day: 15)
        let endDate = TestCalendar.startOfDay(year: 2025, month: 1, day: 20)
        let withinRange = TestCalendar.startOfDay(year: 2025, month: 1, day: 17)
        let outsideRange = TestCalendar.startOfDay(year: 2025, month: 1, day: 25)

        let sl1 = makeTestStudentLesson(scheduledFor: withinRange)
        sl1.scheduledForDay = withinRange
        let sl2 = makeTestStudentLesson(scheduledFor: outsideRange)
        sl2.scheduledForDay = outsideRange
        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let fetched = repository.fetchScheduled(from: startDate, to: endDate)

        #expect(fetched.count == 1)
    }

    @Test("fetchActiveStudentLessons returns items not yet given")
    func fetchActiveStudentLessonsReturnsNotGiven() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl1 = makeTestStudentLesson(givenAt: nil)
        let sl2 = makeTestStudentLesson(givenAt: Date())
        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let fetched = repository.fetchActiveStudentLessons()

        #expect(fetched.count == 1)
        #expect(fetched[0].givenAt == nil)
    }

    @Test("fetchStudentLessons handles empty database")
    func fetchStudentLessonsHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = StudentLessonRepository(context: context)
        let fetched = repository.fetchStudentLessons()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Create Tests

@Suite("StudentLessonRepository Create Tests", .serialized)
@MainActor
struct StudentLessonRepositoryCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("createUnscheduled creates unscheduled item with IDs")
    func createUnscheduledCreatesItemWithIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let studentID = UUID()

        let repository = StudentLessonRepository(context: context)
        let sl = repository.createUnscheduled(lessonID: lessonID, studentIDs: [studentID])

        #expect(sl.lessonID == lessonID.uuidString)
        #expect(sl.studentIDs.contains(studentID.uuidString))
        #expect(sl.scheduledFor == nil)
        #expect(sl.givenAt == nil)
        #expect(sl.isPresented == false)
    }

    @Test("createUnscheduled creates item with relationship objects")
    func createUnscheduledCreatesItemWithRelationships() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math")
        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(lesson)
        context.insert(student)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let sl = repository.createUnscheduled(lesson: lesson, students: [student])

        #expect(sl.lessonID == lesson.id.uuidString)
        #expect(sl.studentIDs.contains(student.id.uuidString))
        #expect(sl.lesson?.id == lesson.id)
        #expect(sl.students.count == 1)
    }

    @Test("createScheduled creates scheduled item")
    func createScheduledCreatesScheduledItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let studentID = UUID()
        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        let repository = StudentLessonRepository(context: context)
        let sl = repository.createScheduled(
            lessonID: lessonID,
            studentIDs: [studentID],
            scheduledFor: scheduledDate
        )

        #expect(sl.lessonID == lessonID.uuidString)
        #expect(sl.scheduledFor != nil)
        #expect(sl.givenAt == nil)
    }

    @Test("createScheduled with relationship objects")
    func createScheduledWithRelationships() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math")
        let student = makeTestStudent(firstName: "Alice", lastName: "Smith")
        context.insert(lesson)
        context.insert(student)
        try context.save()

        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        let repository = StudentLessonRepository(context: context)
        let sl = repository.createScheduled(
            lesson: lesson,
            students: [student],
            scheduledFor: scheduledDate
        )

        #expect(sl.lesson?.id == lesson.id)
        #expect(sl.students.count == 1)
        #expect(sl.scheduledFor != nil)
    }

    @Test("createPresented creates presented item")
    func createPresentedCreatesPresentedItem() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let studentID = UUID()
        let givenDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        let repository = StudentLessonRepository(context: context)
        let sl = repository.createPresented(
            lessonID: lessonID,
            studentIDs: [studentID],
            givenAt: givenDate
        )

        #expect(sl.lessonID == lessonID.uuidString)
        #expect(sl.isPresented == true)
        #expect(sl.givenAt != nil)
    }

    @Test("createPresented persists to context")
    func createPresentedPersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lessonID = UUID()
        let studentID = UUID()

        let repository = StudentLessonRepository(context: context)
        let sl = repository.createPresented(lessonID: lessonID, studentIDs: [studentID])

        let fetched = repository.fetchStudentLesson(id: sl.id)

        #expect(fetched != nil)
        #expect(fetched?.id == sl.id)
    }
}

// MARK: - Update Tests

@Suite("StudentLessonRepository Update Tests", .serialized)
@MainActor
struct StudentLessonRepositoryUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("schedule sets scheduledFor date")
    func scheduleSetsScheduledForDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson(scheduledFor: nil)
        context.insert(sl)
        try context.save()

        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        let repository = StudentLessonRepository(context: context)
        let result = repository.schedule(id: sl.id, for: scheduledDate)

        #expect(result == true)
        #expect(sl.scheduledFor != nil)
    }

    @Test("schedule returns false for missing ID")
    func scheduleReturnsFalseForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = StudentLessonRepository(context: context)
        let result = repository.schedule(id: UUID(), for: Date())

        #expect(result == false)
    }

    @Test("unschedule clears scheduledFor")
    func unscheduleClearsScheduledFor() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let sl = makeTestStudentLesson(scheduledFor: scheduledDate)
        context.insert(sl)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let result = repository.unschedule(id: sl.id)

        #expect(result == true)
        #expect(sl.scheduledFor == nil)
    }

    @Test("markPresented sets isPresented and givenAt")
    func markPresentedSetsFlags() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson(givenAt: nil, isPresented: false)
        context.insert(sl)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let result = repository.markPresented(id: sl.id)

        #expect(result == true)
        #expect(sl.isPresented == true)
        #expect(sl.givenAt != nil)
    }

    @Test("markPresented with custom date")
    func markPresentedWithCustomDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson(givenAt: nil, isPresented: false)
        context.insert(sl)
        try context.save()

        let givenDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        let repository = StudentLessonRepository(context: context)
        let result = repository.markPresented(id: sl.id, givenAt: givenDate)

        #expect(result == true)
        #expect(sl.givenAt == givenDate)
    }

    @Test("updateNotes updates notes field")
    func updateNotesUpdatesField() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson(notes: "")
        context.insert(sl)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let result = repository.updateNotes(id: sl.id, notes: "Student showed great understanding")

        #expect(result == true)
        #expect(sl.latestUnifiedNoteText == "Student showed great understanding")
    }

    @Test("updateFollowUp updates needsPractice flag")
    func updateFollowUpUpdatesNeedsPractice() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson()
        sl.needsPractice = false
        context.insert(sl)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let result = repository.updateFollowUp(id: sl.id, needsPractice: true)

        #expect(result == true)
        #expect(sl.needsPractice == true)
    }

    @Test("updateFollowUp updates needsAnotherPresentation flag")
    func updateFollowUpUpdatesNeedsAnotherPresentation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson()
        sl.needsAnotherPresentation = false
        context.insert(sl)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let result = repository.updateFollowUp(id: sl.id, needsAnotherPresentation: true)

        #expect(result == true)
        #expect(sl.needsAnotherPresentation == true)
    }

    @Test("updateFollowUp updates followUpWork")
    func updateFollowUpUpdatesFollowUpWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson()
        sl.followUpWork = ""
        context.insert(sl)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        let result = repository.updateFollowUp(id: sl.id, followUpWork: "Practice with manipulatives")

        #expect(result == true)
        #expect(sl.followUpWork == "Practice with manipulatives")
    }

    @Test("updateFollowUp only changes specified fields")
    func updateFollowUpOnlyChangesSpecifiedFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson()
        sl.needsPractice = false
        sl.needsAnotherPresentation = true
        sl.followUpWork = "Original work"
        context.insert(sl)
        try context.save()

        let repository = StudentLessonRepository(context: context)
        _ = repository.updateFollowUp(id: sl.id, needsPractice: true)

        #expect(sl.needsPractice == true)
        #expect(sl.needsAnotherPresentation == true) // Unchanged
        #expect(sl.followUpWork == "Original work") // Unchanged
    }
}

// MARK: - Delete Tests

@Suite("StudentLessonRepository Delete Tests", .serialized)
@MainActor
struct StudentLessonRepositoryDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
        ])
    }

    @Test("deleteStudentLesson removes from context")
    func deleteStudentLessonRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson()
        context.insert(sl)
        try context.save()

        let slID = sl.id

        let repository = StudentLessonRepository(context: context)
        try repository.deleteStudentLesson(id: slID)

        let fetched = repository.fetchStudentLesson(id: slID)
        #expect(fetched == nil)
    }

    @Test("deleteStudentLesson does nothing for missing ID")
    func deleteStudentLessonDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = StudentLessonRepository(context: context)
        try repository.deleteStudentLesson(id: UUID())

        // Should not throw
    }
}

#endif
