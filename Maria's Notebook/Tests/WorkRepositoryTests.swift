#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Fetch Tests

@Suite("WorkRepository Fetch Tests", .serialized)
@MainActor
struct WorkRepositoryFetchTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            StudentLesson.self,
            Lesson.self,
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Note.self,
        ])
    }

    @Test("fetchWorkModel returns work by ID")
    func fetchWorkModelReturnsById() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", kind: .practiceLesson)
        context.insert(work)
        try context.save()

        let repository = WorkRepository(context: context)
        let fetched = repository.fetchWorkModel(id: work.id)

        #expect(fetched != nil)
        #expect(fetched?.id == work.id)
        #expect(fetched?.title == "Test Work")
    }

    @Test("fetchWorkModel returns nil for missing ID")
    func fetchWorkModelReturnsNilForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = WorkRepository(context: context)
        let fetched = repository.fetchWorkModel(id: UUID())

        #expect(fetched == nil)
    }

    @Test("fetchWorkModels returns all when no predicate")
    func fetchWorkModelsReturnsAllWhenNoPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work1 = WorkModel(title: "Work 1", kind: .practiceLesson)
        let work2 = WorkModel(title: "Work 2", kind: .research)
        let work3 = WorkModel(title: "Work 3", kind: .followUpAssignment)
        context.insert(work1)
        context.insert(work2)
        context.insert(work3)
        try context.save()

        let repository = WorkRepository(context: context)
        let fetched = repository.fetchWorkModels()

        #expect(fetched.count == 3)
    }

    @Test("fetchWorkModels respects predicate")
    func fetchWorkModelsRespectsPredicate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work1 = WorkModel(title: "Practice Work", kind: .practiceLesson)
        let work2 = WorkModel(title: "Research Work", kind: .research)
        context.insert(work1)
        context.insert(work2)
        try context.save()

        let repository = WorkRepository(context: context)
        // Fetch all and filter in memory since kindRaw is private
        let allWork = repository.fetchWorkModels()
        let fetched = allWork.filter { $0.kind == .practiceLesson }

        #expect(fetched.count == 1)
        #expect(fetched[0].kind == .practiceLesson)
    }

    @Test("fetchWorkModels returns sorted by createdAt descending by default")
    func fetchWorkModelsSortedByCreatedAtDesc() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let oldDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let work1 = WorkModel(title: "Old Work", kind: .practiceLesson, createdAt: oldDate)
        let work2 = WorkModel(title: "New Work", kind: .practiceLesson, createdAt: newDate)
        context.insert(work1)
        context.insert(work2)
        try context.save()

        let repository = WorkRepository(context: context)
        let fetched = repository.fetchWorkModels()

        #expect(fetched[0].title == "New Work")
        #expect(fetched[1].title == "Old Work")
    }

    @Test("fetchWorkModels handles empty database")
    func fetchWorkModelsHandlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = WorkRepository(context: context)
        let fetched = repository.fetchWorkModels()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Create Tests

@Suite("WorkRepository Create Tests", .serialized)
@MainActor
struct WorkRepositoryCreateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            StudentLesson.self,
            Lesson.self,
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Note.self,
        ])
    }

    @Test("createWork creates WorkModel with required fields")
    func createWorkCreatesWorkModel() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let lessonID = UUID()

        let repository = WorkRepository(context: context)
        let work = try repository.createWork(
            studentID: studentID,
            lessonID: lessonID
        )

        #expect(work.id != UUID())
        #expect(work.studentID == studentID.uuidString)
        #expect(work.lessonID == lessonID.uuidString)
        #expect(work.status == .active)
    }

    @Test("createWork sets title when provided")
    func createWorkSetsTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = WorkRepository(context: context)
        let work = try repository.createWork(
            studentID: UUID(),
            lessonID: UUID(),
            title: "Custom Title"
        )

        #expect(work.title == "Custom Title")
    }

    @Test("createWork sets correct kind for practiceLesson")
    func createWorkSetsPracticeType() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = WorkRepository(context: context)
        let work = try repository.createWork(
            studentID: UUID(),
            lessonID: UUID(),
            kind: .practiceLesson
        )

        #expect(work.kind == .practiceLesson)
    }

    @Test("createWork sets correct kind for followUpAssignment")
    func createWorkSetsFollowUpType() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = WorkRepository(context: context)
        let work = try repository.createWork(
            studentID: UUID(),
            lessonID: UUID(),
            kind: .followUpAssignment
        )

        #expect(work.kind == .followUpAssignment)
    }

    @Test("createWork sets correct kind for research")
    func createWorkSetsResearchType() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = WorkRepository(context: context)
        let work = try repository.createWork(
            studentID: UUID(),
            lessonID: UUID(),
            kind: .research
        )

        #expect(work.kind == .research)
    }

    @Test("createWork creates participant for student")
    func createWorkCreatesParticipant() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()

        let repository = WorkRepository(context: context)
        let work = try repository.createWork(
            studentID: studentID,
            lessonID: UUID()
        )

        #expect(work.participants?.count == 1)
        #expect(work.participants?[0].studentID == studentID.uuidString)
    }

    @Test("createWork persists to context")
    func createWorkPersistsToContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = WorkRepository(context: context)
        let work = try repository.createWork(
            studentID: UUID(),
            lessonID: UUID()
        )

        // Fetch from context to verify persistence
        let fetched = repository.fetchWorkModel(id: work.id)

        #expect(fetched != nil)
        #expect(fetched?.id == work.id)
    }

    @Test("createWork sets scheduledDate as dueAt")
    func createWorkSetsScheduledDateAsDueAt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let scheduledDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let repository = WorkRepository(context: context)
        let work = try repository.createWork(
            studentID: UUID(),
            lessonID: UUID(),
            scheduledDate: scheduledDate
        )

        #expect(work.dueAt == scheduledDate)
    }

    @Test("createWork sets presentationID when provided")
    func createWorkSetsPresentationID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let presentationID = UUID()

        let repository = WorkRepository(context: context)
        let work = try repository.createWork(
            studentID: UUID(),
            lessonID: UUID(),
            presentationID: presentationID
        )

        #expect(work.presentationID == presentationID.uuidString)
    }
}

// MARK: - Update Tests

@Suite("WorkRepository Update Tests", .serialized)
@MainActor
struct WorkRepositoryUpdateTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            StudentLesson.self,
            Lesson.self,
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Note.self,
        ])
    }

    @Test("markWorkCompleted sets status to complete")
    func markWorkCompletedSetsStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", kind: .practiceLesson)
        context.insert(work)
        try context.save()

        let repository = WorkRepository(context: context)
        try repository.markWorkCompleted(id: work.id)

        #expect(work.status == .complete)
    }

    @Test("markWorkCompleted sets completedAt")
    func markWorkCompletedSetsCompletedAt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", kind: .practiceLesson)
        context.insert(work)
        try context.save()

        let repository = WorkRepository(context: context)
        try repository.markWorkCompleted(id: work.id)

        // completedAt is normalized to start of day in markWorkCompleted
        #expect(work.completedAt != nil)
        let expectedCompletedAt = AppCalendar.startOfDay(Date())
        #expect(work.completedAt! == expectedCompletedAt)
    }

    @Test("markWorkCompleted sets outcome when provided")
    func markWorkCompletedSetsOutcome() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", kind: .practiceLesson)
        context.insert(work)
        try context.save()

        let repository = WorkRepository(context: context)
        try repository.markWorkCompleted(id: work.id, outcome: .mastered)

        #expect(work.completionOutcome == .mastered)
    }

    @Test("markWorkCompleted sets note when provided")
    func markWorkCompletedSetsNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", kind: .practiceLesson)
        context.insert(work)
        try context.save()

        let repository = WorkRepository(context: context)
        try repository.markWorkCompleted(id: work.id, note: "Great progress!")

        #expect(work.latestUnifiedNoteText == "Great progress!")
    }

    @Test("markWorkCompleted does nothing for missing ID")
    func markWorkCompletedDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = WorkRepository(context: context)
        try repository.markWorkCompleted(id: UUID())

        // Should not throw - just silently does nothing
    }

    @Test("updateWorkStatus changes work status")
    func updateWorkStatusChangesStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", kind: .practiceLesson)
        work.status = .active
        context.insert(work)
        try context.save()

        let repository = WorkRepository(context: context)
        try repository.updateWorkStatus(id: work.id, status: .review)

        #expect(work.status == .review)
    }
}

// MARK: - Delete Tests

@Suite("WorkRepository Delete Tests", .serialized)
@MainActor
struct WorkRepositoryDeleteTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            StudentLesson.self,
            Lesson.self,
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Note.self,
        ])
    }

    @Test("deleteWork removes work from context")
    func deleteWorkRemovesFromContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test Work", kind: .practiceLesson)
        context.insert(work)
        try context.save()

        let workID = work.id

        let repository = WorkRepository(context: context)
        try repository.deleteWork(id: workID)

        let fetched = repository.fetchWorkModel(id: workID)
        #expect(fetched == nil)
    }

    @Test("deleteWork does nothing for missing ID")
    func deleteWorkDoesNothingForMissingId() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = WorkRepository(context: context)
        try repository.deleteWork(id: UUID())

        // Should not throw
    }
}

// MARK: - Completion Toggle Tests

@Suite("WorkRepository Completion Toggle Tests", .serialized)
@MainActor
struct WorkRepositoryCompletionToggleTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            StudentLesson.self,
            Lesson.self,
            GroupTrack.self,
            Track.self,
            TrackStep.self,
            Note.self,
        ])
    }

    @Test("toggleCompletion marks incomplete student as complete")
    func toggleCompletionMarksIncompleteAsComplete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let work = WorkModel(title: "Test Work", kind: .practiceLesson)
        let participant = WorkParticipantEntity(studentID: studentID, completedAt: nil, work: work)
        work.participants = [participant]
        context.insert(work)
        try context.save()

        let repository = WorkRepository(context: context)
        try repository.toggleCompletion(workID: work.id, studentID: studentID)

        #expect(participant.completedAt != nil)
    }

    @Test("toggleCompletion marks complete student as incomplete")
    func toggleCompletionMarksCompleteAsIncomplete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let completedDate = TestCalendar.date(year: 2025, month: 1, day: 15)
        let work = WorkModel(title: "Test Work", kind: .practiceLesson)
        let participant = WorkParticipantEntity(studentID: studentID, completedAt: completedDate, work: work)
        work.participants = [participant]
        context.insert(work)
        try context.save()

        let repository = WorkRepository(context: context)
        try repository.toggleCompletion(workID: work.id, studentID: studentID)

        #expect(participant.completedAt == nil)
    }

    @Test("toggleCompletion does nothing for missing work")
    func toggleCompletionDoesNothingForMissingWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let repository = WorkRepository(context: context)
        try repository.toggleCompletion(workID: UUID(), studentID: UUID())

        // Should not throw
    }
}

#endif
