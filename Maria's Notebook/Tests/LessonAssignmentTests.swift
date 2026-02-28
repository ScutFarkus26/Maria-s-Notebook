#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - LessonAssignment Model Tests

@Suite("LessonAssignment Model")
struct LessonAssignmentModelTests {

    // MARK: - State Lifecycle

    @Test("Draft is the default state")
    @MainActor func draftIsDefault() throws {
        let la = PresentationFactory.makeDraft(
            lessonID: UUID(),
            studentIDs: [UUID()]
        )
        #expect(la.state == .draft)
        #expect(la.isDraft)
        #expect(!la.isPresented)
        #expect(!la.isScheduled)
        #expect(la.scheduledFor == nil)
        #expect(la.presentedAt == nil)
    }

    @Test("Schedule transitions draft to scheduled")
    @MainActor func scheduleTransition() throws {
        let la = PresentationFactory.makeDraft(
            lessonID: UUID(),
            studentIDs: [UUID()]
        )
        let scheduleDate = testDate(year: 2026, month: 3, day: 15)
        la.schedule(for: scheduleDate)

        #expect(la.state == .scheduled)
        #expect(la.isScheduled)
        #expect(!la.isDraft)
        #expect(!la.isPresented)
        #expect(la.scheduledFor != nil)
        expectSameDay(la.scheduledFor!, scheduleDate)
    }

    @Test("Unschedule returns to draft state")
    @MainActor func unscheduleTransition() throws {
        let la = PresentationFactory.makeScheduled(
            lessonID: UUID(),
            studentIDs: [UUID()],
            scheduledFor: Date()
        )
        la.unschedule()

        #expect(la.state == .draft)
        #expect(la.isDraft)
        #expect(la.scheduledFor == nil)
    }

    @Test("markPresented transitions to presented")
    @MainActor func markPresentedTransition() throws {
        let la = PresentationFactory.makeScheduled(
            lessonID: UUID(),
            studentIDs: [UUID()],
            scheduledFor: Date()
        )
        let presentedDate = testDate(year: 2026, month: 3, day: 15, hour: 10)
        la.markPresented(at: presentedDate, snapshotLesson: false)

        #expect(la.state == .presented)
        #expect(la.isPresented)
        #expect(la.presentedAt == presentedDate)
    }

    @Test("markPresented snapshots lesson title")
    @MainActor func markPresentedSnapshotsLesson() throws {
        let container = try makeTestContainer(for: [
            Student.self, Lesson.self, LessonAssignment.self
        ])
        let context = container.mainContext
        let lesson = makeTestLesson(name: "Addition Basics", subheading: "Numbers 1-10")
        context.insert(lesson)
        let la = PresentationFactory.makeDraft(
            lessonID: lesson.id,
            studentIDs: [UUID()]
        )
        la.lesson = lesson
        context.insert(la)
        try context.save()

        la.markPresented(at: Date(), snapshotLesson: true)

        #expect(la.lessonTitleSnapshot == "Addition Basics")
        #expect(la.lessonSubheadingSnapshot == "Numbers 1-10")
    }

    // MARK: - Student IDs

    @Test("Student IDs round-trip correctly")
    @MainActor func studentIDsRoundTrip() throws {
        let studentIDs = [UUID(), UUID(), UUID()]
        let la = PresentationFactory.makeDraft(
            lessonID: UUID(),
            studentIDs: studentIDs
        )
        #expect(la.studentUUIDs.count == 3)
        #expect(Set(la.studentUUIDs) == Set(studentIDs))
    }

    @Test("Empty student IDs are valid")
    @MainActor func emptyStudentIDs() throws {
        let la = PresentationFactory.makeDraft(
            lessonID: UUID(),
            studentIDs: []
        )
        #expect(la.studentUUIDs.isEmpty)
        #expect(la.studentIDs.isEmpty)
    }

    // MARK: - Lesson ID

    @Test("Lesson ID stored as string, accessible as UUID")
    @MainActor func lessonIDAccessors() throws {
        let lessonID = UUID()
        let la = PresentationFactory.makeDraft(
            lessonID: lessonID,
            studentIDs: []
        )
        #expect(la.lessonID == lessonID.uuidString)
        #expect(la.lessonIDUUID == lessonID)
    }

    // MARK: - Planning Flags

    @Test("Planning flags default to false/empty")
    @MainActor func defaultFlags() throws {
        let la = PresentationFactory.makeDraft(
            lessonID: UUID(),
            studentIDs: []
        )
        #expect(!la.needsPractice)
        #expect(!la.needsAnotherPresentation)
        #expect(la.followUpWork.isEmpty)
        #expect(la.notes.isEmpty)
        #expect(!la.manuallyUnblocked)
    }

    @Test("Planning flags can be set")
    @MainActor func setFlags() throws {
        let la = PresentationFactory.makeDraft(
            lessonID: UUID(),
            studentIDs: []
        )
        la.needsPractice = true
        la.needsAnotherPresentation = true
        la.followUpWork = "Practice with bead material"
        la.notes = "Student showed good understanding"
        la.manuallyUnblocked = true

        #expect(la.needsPractice)
        #expect(la.needsAnotherPresentation)
        #expect(la.followUpWork == "Practice with bead material")
        #expect(la.notes == "Student showed good understanding")
        #expect(la.manuallyUnblocked)
    }

    // MARK: - Snapshot

    @Test("Snapshot captures current state")
    @MainActor func snapshotCapture() throws {
        let lessonID = UUID()
        let studentIDs = [UUID(), UUID()]
        let la = PresentationFactory.makePresented(
            lessonID: lessonID,
            studentIDs: studentIDs,
            presentedAt: testDate(year: 2026, month: 1, day: 15)
        )
        la.needsPractice = true
        la.notes = "Good work"

        let snap = la.snapshot()

        #expect(snap.id == la.id)
        #expect(snap.lessonID == lessonID)
        #expect(snap.studentIDs.count == 2)
        #expect(snap.state == .presented)
        #expect(snap.isPresented)
        #expect(snap.needsPractice)
        #expect(snap.notes == "Good work")
    }
}

// MARK: - PresentationFactory Tests

@Suite("PresentationFactory")
struct PresentationFactoryTests {

    @Test("makeDraft creates draft state")
    @MainActor func makeDraft() throws {
        let la = PresentationFactory.makeDraft(
            lessonID: UUID(),
            studentIDs: [UUID()]
        )
        #expect(la.state == .draft)
        #expect(la.scheduledFor == nil)
        #expect(la.presentedAt == nil)
    }

    @Test("makeScheduled creates scheduled state")
    @MainActor func makeScheduled() throws {
        let date = testDate(year: 2026, month: 3, day: 1)
        let la = PresentationFactory.makeScheduled(
            lessonID: UUID(),
            studentIDs: [UUID()],
            scheduledFor: date
        )
        #expect(la.state == .scheduled)
        #expect(la.scheduledFor != nil)
        expectSameDay(la.scheduledFor!, date)
    }

    @Test("makePresented creates presented state")
    @MainActor func makePresented() throws {
        let date = testDate(year: 2026, month: 2, day: 28)
        let la = PresentationFactory.makePresented(
            lessonID: UUID(),
            studentIDs: [UUID()],
            presentedAt: date
        )
        #expect(la.state == .presented)
        #expect(la.presentedAt == date)
    }

    @Test("attachRelationships wires lesson and students")
    @MainActor func attachRelationships() throws {
        let container = try makeTestContainer(for: [
            Student.self, Lesson.self, LessonAssignment.self
        ])
        let context = container.mainContext
        let lesson = makeTestLesson(name: "Subtraction")
        let student = makeTestStudent(firstName: "Alice")
        context.insert(lesson)
        context.insert(student)
        try context.save()

        let la = PresentationFactory.makeDraft(
            lessonID: lesson.id,
            studentIDs: [student.id]
        )
        PresentationFactory.attachRelationships(to: la, lesson: lesson, students: [student])

        #expect(la.lesson?.id == lesson.id)
        #expect(la.students.count == 1)
        #expect(la.students.first?.id == student.id)
    }

    @Test("insertDraft creates and inserts in one step")
    @MainActor func insertDraft() throws {
        let container = try makeTestContainer(for: [
            Student.self, Lesson.self, LessonAssignment.self
        ])
        let context = container.mainContext
        let lessonID = UUID()

        let la = PresentationFactory.insertDraft(
            lessonID: lessonID,
            studentIDs: [UUID()],
            context: context
        )
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.id == la.id)
        #expect(fetched.first?.state == .draft)
    }
}

// MARK: - Persistence Tests

@Suite("LessonAssignment Persistence")
struct LessonAssignmentPersistenceTests {

    @Test("Draft persists and fetches correctly")
    @MainActor func draftPersistence() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext
        let builder = TestEntityBuilder(context: context)

        let student = try builder.buildStudent(firstName: "Bob")
        let lesson = try builder.buildLesson(name: "Reading")
        let la = try builder.buildLessonAssignment(lesson: lesson, students: [student])

        let fetched = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.state == .draft)
        #expect(fetched.first?.lessonIDUUID == lesson.id)
    }

    @Test("State changes persist after save")
    @MainActor func stateChangePersistence() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext
        let builder = TestEntityBuilder(context: context)

        let student = try builder.buildStudent()
        let lesson = try builder.buildLesson()
        let la = try builder.buildLessonAssignment(lesson: lesson, students: [student])

        la.schedule(for: testDate(year: 2026, month: 4, day: 1))
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(fetched.first?.state == .scheduled)

        fetched.first?.markPresented(at: testDate(year: 2026, month: 4, day: 1), snapshotLesson: false)
        try context.save()

        let refetched = try context.fetch(FetchDescriptor<LessonAssignment>())
        #expect(refetched.first?.state == .presented)
    }

    @Test("Predicate filters by state")
    @MainActor func predicateStateFilter() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext
        let builder = TestEntityBuilder(context: context)

        let student = try builder.buildStudent()
        let lesson1 = try builder.buildLesson(name: "Lesson A")
        let lesson2 = try builder.buildLesson(name: "Lesson B")
        let lesson3 = try builder.buildLesson(name: "Lesson C")

        _ = try builder.buildLessonAssignment(lesson: lesson1, students: [student])
        _ = try builder.buildLessonAssignment(lesson: lesson2, students: [student], scheduledFor: Date())
        _ = try builder.buildLessonAssignment(lesson: lesson3, students: [student], presentedAt: Date())

        let draftRaw = LessonAssignmentState.draft.rawValue
        let draftPredicate = #Predicate<LessonAssignment> { $0.stateRaw == draftRaw }
        let drafts = try context.fetch(FetchDescriptor<LessonAssignment>(predicate: draftPredicate))
        #expect(drafts.count == 1)

        let presentedRaw = LessonAssignmentState.presented.rawValue
        let presentedPredicate = #Predicate<LessonAssignment> { $0.stateRaw == presentedRaw }
        let presented = try context.fetch(FetchDescriptor<LessonAssignment>(predicate: presentedPredicate))
        #expect(presented.count == 1)
    }

    @Test("Predicate filters by lessonID")
    @MainActor func predicateLessonIDFilter() throws {
        let container = try makeStandardTestContainer()
        let context = container.mainContext
        let builder = TestEntityBuilder(context: context)

        let student = try builder.buildStudent()
        let lesson1 = try builder.buildLesson(name: "Target Lesson")
        let lesson2 = try builder.buildLesson(name: "Other Lesson")

        _ = try builder.buildLessonAssignment(lesson: lesson1, students: [student])
        _ = try builder.buildLessonAssignment(lesson: lesson2, students: [student])

        let targetID = lesson1.id.uuidString
        let predicate = #Predicate<LessonAssignment> { $0.lessonID == targetID }
        let results = try context.fetch(FetchDescriptor<LessonAssignment>(predicate: predicate))
        #expect(results.count == 1)
        #expect(results.first?.lessonIDUUID == lesson1.id)
    }
}

#endif
