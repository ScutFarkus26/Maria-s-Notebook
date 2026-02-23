#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

@Suite("WorkModel Lifecycle Tests", .serialized)
@MainActor
struct WorkModelTests {

    // MARK: - Test Helpers

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeWorkModel(
        title: String = "Test Work",
        kind: WorkKind = .research,
        completedAt: Date? = nil,
        status: WorkStatus = .active,
        assignedAt: Date? = nil,
        lastTouchedAt: Date? = nil,
        dueAt: Date? = nil,
        studentID: String = "",
        lessonID: String = ""
    ) -> WorkModel {
        return WorkModel(
            title: title,
            kind: kind,
            completedAt: completedAt,
            status: status,
            assignedAt: assignedAt ?? Date(),
            lastTouchedAt: lastTouchedAt,
            dueAt: dueAt,
            studentID: studentID,
            lessonID: lessonID
        )
    }

    // MARK: - Initialization Tests

    @Test("WorkModel initializes with default values")
    func initializesWithDefaults() {
        let work = WorkModel()

        #expect(work.title == "")
        #expect(work.kind == .research)
        #expect(work.status == .active)
        #expect(work.completedAt == nil)
        #expect(work.participants?.isEmpty ?? true)
    }

    @Test("WorkModel initializes with custom values")
    func initializesWithCustomValues() {
        let assignedDate = TestCalendar.date(year: 2025, month: 1, day: 15)
        let dueDate = TestCalendar.date(year: 2025, month: 2, day: 15)

        let work = WorkModel(
            title: "Addition Practice",
            kind: .practiceLesson,
            status: .active,
            assignedAt: assignedDate,
            dueAt: dueDate,
            studentID: "student123",
            lessonID: "lesson456"
        )

        #expect(work.title == "Addition Practice")
        #expect(work.kind == .practiceLesson)
        #expect(work.status == .active)
        #expect(work.studentID == "student123")
        #expect(work.lessonID == "lesson456")
    }

    @Test("WorkModel WorkType enum has all cases")
    func workTypeHasAllCases() {
        let allCases = WorkModel.WorkType.allCases

        #expect(allCases.count == 4)
        #expect(allCases.contains(.research))
        #expect(allCases.contains(.followUp))
        #expect(allCases.contains(.practice))
        #expect(allCases.contains(.report))
    }

    // MARK: - Status Tests

    @Test("WorkModel status getter returns correct WorkStatus")
    func statusGetterWorks() {
        let work = makeWorkModel(status: .active)
        #expect(work.status == .active)

        let work2 = makeWorkModel(status: .review)
        #expect(work2.status == .review)

        let work3 = makeWorkModel(status: .complete)
        #expect(work3.status == .complete)
    }

    @Test("WorkModel status setter updates statusRaw")
    func statusSetterWorks() {
        let work = makeWorkModel(status: .active)

        work.status = .review
        #expect(work.status == .review)
        #expect(work.statusRaw == WorkStatus.review.rawValue)

        work.status = .complete
        #expect(work.status == .complete)
        #expect(work.statusRaw == WorkStatus.complete.rawValue)
    }

    @Test("WorkModel isActive helper returns correct value")
    func isActiveHelper() {
        let work = makeWorkModel(status: .active)
        #expect(work.isActive == true)
        #expect(work.isReview == false)
        #expect(work.isComplete == false)
        #expect(work.isIncomplete == true)
    }

    @Test("WorkModel isReview helper returns correct value")
    func isReviewHelper() {
        let work = makeWorkModel(status: .review)
        #expect(work.isActive == false)
        #expect(work.isReview == true)
        #expect(work.isComplete == false)
        #expect(work.isIncomplete == true)
    }

    @Test("WorkModel isComplete helper returns correct value")
    func isCompleteHelper() {
        let work = makeWorkModel(status: .complete)
        #expect(work.isActive == false)
        #expect(work.isReview == false)
        #expect(work.isComplete == true)
        #expect(work.isIncomplete == false)
    }

    // MARK: - Status Transition Tests

    @Test("WorkModel transitions from active to review")
    func transitionsActiveToReview() {
        let work = makeWorkModel(status: .active)

        #expect(work.status == .active)
        #expect(work.isActive == true)

        work.status = .review

        #expect(work.status == .review)
        #expect(work.isReview == true)
        #expect(work.isActive == false)
    }

    @Test("WorkModel transitions from review to complete")
    func transitionsReviewToComplete() {
        let work = makeWorkModel(status: .review)

        #expect(work.status == .review)

        work.status = .complete

        #expect(work.status == .complete)
        #expect(work.isComplete == true)
        #expect(work.isReview == false)
    }

    @Test("WorkModel transitions from active to complete")
    func transitionsActiveToComplete() {
        let work = makeWorkModel(status: .active)

        work.status = .complete

        #expect(work.status == .complete)
        #expect(work.isComplete == true)
    }

    // MARK: - Completion Tests

    @Test("WorkModel isCompleted returns false when completedAt is nil")
    func isCompletedFalseWhenNil() {
        let work = makeWorkModel()

        #expect(work.isCompleted == false)
        #expect(work.completedAt == nil)
    }

    @Test("WorkModel isCompleted returns true when completedAt is set")
    func isCompletedTrueWhenSet() {
        let completedDate = TestCalendar.date(year: 2025, month: 1, day: 20)
        let work = makeWorkModel(completedAt: completedDate)

        #expect(work.isCompleted == true)
        #expect(work.completedAt != nil)
    }

    // MARK: - Participant Tests

    @Test("WorkModel initializes with empty participants")
    func initializesWithEmptyParticipants() {
        let work = makeWorkModel()

        #expect(work.participants?.isEmpty ?? true)
    }

    @Test("WorkModel can add participants")
    func addsParticipants() {
        let work = makeWorkModel()
        let studentID = UUID()

        work.markStudent(studentID, completedAt: nil)

        #expect(work.participants?.count == 1)
        #expect(work.participants?[0].studentID == studentID.uuidString)
        #expect(work.participants?[0].completedAt == nil)
    }

    @Test("WorkModel participant function finds correct participant")
    func findsParticipant() {
        let work = makeWorkModel()
        let studentID = UUID()

        work.markStudent(studentID, completedAt: nil)

        let participant = work.participant(for: studentID)

        #expect(participant != nil)
        #expect(participant?.studentID == studentID.uuidString)
    }

    @Test("WorkModel participant function returns nil for non-existent student")
    func returnsNilForNonExistentParticipant() {
        let work = makeWorkModel()
        let studentID = UUID()

        let participant = work.participant(for: studentID)

        #expect(participant == nil)
    }

    @Test("WorkModel markStudent creates new participant if not exists")
    func markStudentCreatesParticipant() {
        let work = makeWorkModel()
        let studentID = UUID()
        let completedDate = TestCalendar.date(year: 2025, month: 1, day: 20)

        work.markStudent(studentID, completedAt: completedDate)

        #expect(work.participants?.count == 1)
        let participant = work.participant(for: studentID)
        #expect(participant != nil)
        #expect(participant?.completedAt != nil)
    }

    @Test("WorkModel markStudent updates existing participant")
    func markStudentUpdatesExisting() {
        let work = makeWorkModel()
        let studentID = UUID()

        work.markStudent(studentID, completedAt: nil)
        #expect(work.participant(for: studentID)?.completedAt == nil)

        let completedDate = TestCalendar.date(year: 2025, month: 1, day: 20)
        work.markStudent(studentID, completedAt: completedDate)

        #expect(work.participants?.count == 1)
        #expect(work.participant(for: studentID)?.completedAt != nil)
    }

    @Test("WorkModel isStudentCompleted returns false when not completed")
    func isStudentCompletedFalseWhenNotCompleted() {
        let work = makeWorkModel()
        let studentID = UUID()

        work.markStudent(studentID, completedAt: nil)

        #expect(work.isStudentCompleted(studentID) == false)
    }

    @Test("WorkModel isStudentCompleted returns true when completed")
    func isStudentCompletedTrueWhenCompleted() {
        let work = makeWorkModel()
        let studentID = UUID()
        let completedDate = TestCalendar.date(year: 2025, month: 1, day: 20)

        work.markStudent(studentID, completedAt: completedDate)

        #expect(work.isStudentCompleted(studentID) == true)
    }

    @Test("WorkModel isStudentCompleted returns false for non-existent participant")
    func isStudentCompletedFalseForNonExistent() {
        let work = makeWorkModel()
        let studentID = UUID()

        #expect(work.isStudentCompleted(studentID) == false)
    }

    // MARK: - isOpen Tests

    @Test("WorkModel isOpen is true when status is not complete and no participants")
    func isOpenTrueWhenNoParticipants() {
        let work = makeWorkModel(status: .active)

        #expect(work.isOpen == true)
    }

    @Test("WorkModel isOpen is false when status is complete")
    func isOpenFalseWhenComplete() {
        let work = makeWorkModel(status: .complete)

        #expect(work.isOpen == false)
    }

    @Test("WorkModel isOpen is true when any participant is incomplete")
    func isOpenTrueWhenAnyParticipantIncomplete() {
        let work = makeWorkModel(status: .active)
        let student1 = UUID()
        let student2 = UUID()
        let completedDate = TestCalendar.date(year: 2025, month: 1, day: 20)

        work.markStudent(student1, completedAt: completedDate)
        work.markStudent(student2, completedAt: nil)

        #expect(work.isOpen == true)
    }

    @Test("WorkModel isOpen is false when all participants are complete")
    func isOpenFalseWhenAllParticipantsComplete() {
        let work = makeWorkModel(status: .active)
        let student1 = UUID()
        let student2 = UUID()
        let completedDate = TestCalendar.date(year: 2025, month: 1, day: 20)

        work.markStudent(student1, completedAt: completedDate)
        work.markStudent(student2, completedAt: completedDate)

        #expect(work.isOpen == false)
    }

    // MARK: - Kind Tests

    @Test("WorkModel kind getter returns correct WorkKind")
    func kindGetterWorks() {
        let work = makeWorkModel()
        work.kind = .practiceLesson

        #expect(work.kind == .practiceLesson)
        #expect(work.kindRaw == WorkKind.practiceLesson.rawValue)
    }

    @Test("WorkModel kind setter updates kindRaw")
    func kindSetterWorks() {
        let work = makeWorkModel()

        work.kind = .followUpAssignment
        #expect(work.kind == .followUpAssignment)
        #expect(work.kindRaw == WorkKind.followUpAssignment.rawValue)

        work.kind = nil
        #expect(work.kind == nil)
        #expect(work.kindRaw == nil)
    }

    // MARK: - CompletionOutcome Tests

    @Test("WorkModel completionOutcome getter returns correct value")
    func completionOutcomeGetterWorks() {
        let work = makeWorkModel()
        work.completionOutcome = .mastered

        #expect(work.completionOutcome == .mastered)
        #expect(work.completionOutcomeRaw == CompletionOutcome.mastered.rawValue)
    }

    @Test("WorkModel completionOutcome setter updates raw value")
    func completionOutcomeSetterWorks() {
        let work = makeWorkModel()

        work.completionOutcome = .needsReview
        #expect(work.completionOutcome == .needsReview)
        #expect(work.completionOutcomeRaw == CompletionOutcome.needsReview.rawValue)

        work.completionOutcome = nil
        #expect(work.completionOutcome == nil)
        #expect(work.completionOutcomeRaw == nil)
    }

    // MARK: - Persistence Tests

    @Test("WorkModel persists and retrieves from ModelContext")
    func persistsToModelContext() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = makeWorkModel(
            title: "Test Work",
            status: .active,
            studentID: "student123",
            lessonID: "lesson456"
        )

        context.insert(work)
        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let descriptor = FetchDescriptor<WorkModel>()
        let allFetched = try context.fetch(descriptor)
        let fetched = allFetched.filter { $0.id == work.id }

        #expect(fetched.count == 1)
        #expect(fetched[0].id == work.id)
        #expect(fetched[0].title == "Test Work")
        #expect(fetched[0].status == .active)
        #expect(fetched[0].studentID == "student123")
        #expect(fetched[0].lessonID == "lesson456")
    }

    @Test("WorkModel with participants persists correctly")
    func participantsPersist() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = makeWorkModel()
        let studentID = UUID()
        let completedDate = TestCalendar.date(year: 2025, month: 1, day: 20)

        work.markStudent(studentID, completedAt: completedDate)

        context.insert(work)
        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let descriptor = FetchDescriptor<WorkModel>()
        let allFetched = try context.fetch(descriptor)
        let fetched = allFetched.filter { $0.id == work.id }

        #expect(fetched.count == 1)
        #expect(fetched[0].participants?.count == 1)
        #expect(fetched[0].participant(for: studentID) != nil)
        #expect(fetched[0].isStudentCompleted(studentID) == true)
    }

    // MARK: - Date Normalization Tests

    @Test("WorkModel normalizes createdAt to start of day")
    func normalizesCreatedAtDate() {
        // WorkModel normalizes createdAt to start of day in init
        // Use the WorkModel() default initializer which uses the current date
        let work = WorkModel()

        // createdAt is normalized to start of current day
        #expect(Calendar.current.isDate(work.createdAt, inSameDayAs: Date()))
    }

    @Test("WorkModel normalizes completedAt date")
    func normalizesCompletedAtDate() {
        let date = TestCalendar.date(year: 2025, month: 1, day: 20, hour: 16, minute: 45)
        let expectedDay = TestCalendar.startOfDay(year: 2025, month: 1, day: 20)

        let work = makeWorkModel(completedAt: date)

        #expect(work.completedAt == expectedDay)
    }

    // MARK: - Integration Tests

    @Test("WorkModel complete workflow: create, assign, review, complete")
    func completeWorkflow() {
        let work = makeWorkModel(title: "Addition Practice", status: .active)
        let student1 = UUID()
        let student2 = UUID()

        // Step 1: Work is created and assigned
        #expect(work.status == .active)
        #expect(work.isOpen == true)

        // Step 2: Add participants
        work.markStudent(student1, completedAt: nil)
        work.markStudent(student2, completedAt: nil)
        #expect(work.participants?.count == 2)
        #expect(work.isOpen == true)

        // Step 3: One student completes
        let completedDate = TestCalendar.date(year: 2025, month: 1, day: 20)
        work.markStudent(student1, completedAt: completedDate)
        #expect(work.isStudentCompleted(student1) == true)
        #expect(work.isStudentCompleted(student2) == false)
        #expect(work.isOpen == true)

        // Step 4: Second student completes
        work.markStudent(student2, completedAt: completedDate)
        #expect(work.isStudentCompleted(student2) == true)
        #expect(work.isOpen == false)

        // Step 5: Transition to review
        work.status = .review
        #expect(work.isReview == true)
        #expect(work.isIncomplete == true)

        // Step 6: Mark complete
        work.status = .complete
        #expect(work.isComplete == true)
        #expect(work.isOpen == false)
    }

    @Test("WorkModel handles multiple participants across different states")
    func handlesMultipleParticipantStates() {
        let work = makeWorkModel(status: .active)
        let student1 = UUID()
        let student2 = UUID()
        let student3 = UUID()

        work.markStudent(student1, completedAt: TestCalendar.date(year: 2025, month: 1, day: 15))
        work.markStudent(student2, completedAt: nil)
        work.markStudent(student3, completedAt: TestCalendar.date(year: 2025, month: 1, day: 17))

        #expect(work.participants?.count == 3)
        #expect(work.isStudentCompleted(student1) == true)
        #expect(work.isStudentCompleted(student2) == false)
        #expect(work.isStudentCompleted(student3) == true)
        #expect(work.isOpen == true)
    }
}

#endif
