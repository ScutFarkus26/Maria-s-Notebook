import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The checklist's status ladder (plan, Phase 2): one rung per cell, green only for a
/// mastery mark, closed work without a mark on Reviewing, and Ready / Not yet ready
/// split by the blocking reason.
@Suite("Checklist display status")
@MainActor
struct ChecklistDisplayStatusTests {

    private func state(
        isScheduled: Bool = false,
        isPresented: Bool = false,
        isComplete: Bool = false,
        isWorkActive: Bool = false,
        isWorkReview: Bool = false,
        isStale: Bool = false,
        blockingReason: BlockingReason = .none,
        isMastered: Bool = false
    ) -> StudentChecklistRowState {
        StudentChecklistRowState(
            lessonID: UUID(), plannedItemID: nil, presentationLogID: nil, contractID: nil,
            isScheduled: isScheduled, isPresented: isPresented, isActive: isWorkActive || isWorkReview,
            isComplete: isComplete, isWorkActive: isWorkActive, isWorkReview: isWorkReview,
            lastActivityDate: nil, isStale: isStale, blockingReason: blockingReason, isMastered: isMastered
        )
    }

    // MARK: - Derivation

    @Test("Not presented and blocked is Not yet ready, whatever the reason")
    func notPresentedBlockedIsNotReady() {
        for reason in [BlockingReason.prerequisiteNotPresented, .practiceRequired,
                       .confirmationRequired, .practiceAndConfirmation] {
            #expect(state(blockingReason: reason).displayStatus == .notReady)
        }
    }

    @Test("Not presented and unblocked is Ready")
    func notPresentedUnblockedIsReady() {
        #expect(state().displayStatus == .ready)
    }

    @Test("A plan is Planned, even before the lesson ahead of it is done")
    func plannedBeatsBlocked() {
        #expect(state(isScheduled: true).displayStatus == .planned)
        #expect(state(isScheduled: true, blockingReason: .prerequisiteNotPresented).displayStatus == .planned)
    }

    @Test("Presented, practicing and reviewing climb in order")
    func blueRungs() {
        #expect(state(isScheduled: true, isPresented: true).displayStatus == .presented)
        #expect(state(isPresented: true, isWorkActive: true).displayStatus == .practicing)
        #expect(state(isPresented: true, isWorkReview: true).displayStatus == .reviewing)
    }

    @Test("Closed work without a mastery mark is Reviewing, not Mastered")
    func closedWorkWithoutMarkIsReviewing() {
        #expect(state(isPresented: true, isComplete: true).displayStatus == .reviewing)
    }

    @Test("A mastery mark is Mastered, with or without closed work")
    func markIsMastered() {
        #expect(state(isMastered: true).displayStatus == .mastered)
        #expect(state(isPresented: true, isComplete: true, isMastered: true).displayStatus == .mastered)
        #expect(state(isPresented: true, isWorkActive: true, isMastered: true).displayStatus == .mastered)
    }

    @Test("Stale work asks for a check-in until the lesson is mastered")
    func checkIn() {
        #expect(state(isPresented: true, isWorkActive: true, isStale: true).needsCheckIn)
        #expect(!state(isPresented: true, isWorkActive: true).needsCheckIn)
        #expect(!state(isWorkActive: true, isStale: true, isMastered: true).needsCheckIn)
    }

    // MARK: - From the Store

    /// Ada, Bruno, Chava, Dov; Math › Decimal 0–2 (default rules: practice and confirmation).
    private struct Fixture {
        let viewModel: ClassAreaChecklistViewModel
        let context: NSManagedObjectContext
        let ada: CDStudent
        let bruno: CDStudent
        let chava: CDStudent
        let dov: CDStudent
        let decimal: [CDLesson]

        func status(_ student: CDStudent, _ index: Int) -> ChecklistDisplayStatus? {
            viewModel.state(for: student, lesson: decimal[index])?.displayStatus
        }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Test")
        let bruno = CoreDataTestHelpers.seedStudent(in: context, firstName: "Bruno", lastName: "Test")
        let chava = CoreDataTestHelpers.seedStudent(in: context, firstName: "Chava", lastName: "Test")
        let dov = CoreDataTestHelpers.seedStudent(in: context, firstName: "Dov", lastName: "Test")
        let decimal = (0..<3).map { order in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Decimal \(order)", area: "Math", sequence: "Decimal"
            )
            lesson.orderInSequence = Int64(order)
            return lesson
        }
        let firstID = try #require(decimal[0].id).uuidString

        // Ada: presented, practiced, work closed, no mark.
        let given = CDLessonAssignment(context: context)
        given.lessonID = firstID
        given.studentIDs = [ada.cloudKitKey]
        given.markPresented(at: Date(timeIntervalSince1970: 1_780_000_000))
        let work = CDWorkModel(context: context)
        work.lessonID = firstID
        work.status = .mastered
        work.createdAt = Date()
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = ada.cloudKitKey
        participant.work = work

        // Bruno: a proficient mark and nothing else.
        let brunoMark = CDLessonPresentation(context: context)
        brunoMark.studentID = bruno.cloudKitKey
        brunoMark.lessonID = firstID
        brunoMark.state = .proficient

        // Chava: a presented-state row that carries masteredAt.
        let chavaMark = CDLessonPresentation(context: context)
        chavaMark.studentID = chava.cloudKitKey
        chavaMark.lessonID = firstID
        chavaMark.masteredAt = Date(timeIntervalSince1970: 1_781_000_000)

        // A plain presented row is not a mark.
        let dovRow = CDLessonPresentation(context: context)
        dovRow.studentID = dov.cloudKitKey
        dovRow.lessonID = try #require(decimal[2].id).uuidString
        try context.save()

        let viewModel = ClassAreaChecklistViewModel()
        viewModel.selectedArea = "Math"
        viewModel.loadData(context: context)
        viewModel.applyVisibilityFilter(context: context, show: true, namesRaw: "")
        return Fixture(
            viewModel: viewModel, context: context,
            ada: ada, bruno: bruno, chava: chava, dov: dov, decimal: decimal
        )
    }

    @Test("The builder reads marks: closed work alone is Reviewing, a mark alone is Mastered")
    func builderReadsMarks() throws {
        let fixture = try makeFixture()
        #expect(fixture.status(fixture.ada, 0) == .reviewing)
        #expect(fixture.status(fixture.bruno, 0) == .mastered)
        #expect(fixture.status(fixture.chava, 0) == .mastered)
        #expect(fixture.viewModel.state(for: fixture.dov, lesson: fixture.decimal[2])?.isMastered == false)
    }

    @Test("The builder splits Ready from Not yet ready, and shows a plan as Planned")
    func builderReadyNotReadyPlanned() throws {
        let fixture = try makeFixture()
        // The first lesson of a sequence has nothing ahead of it.
        #expect(fixture.status(fixture.dov, 0) == .ready)
        // Decimal 1 waits on Decimal 0 being presented.
        #expect(fixture.status(fixture.dov, 1) == .notReady)

        fixture.viewModel.toggleScheduled(student: fixture.dov, lesson: fixture.decimal[1], context: fixture.context)
        #expect(fixture.status(fixture.dov, 1) == .planned)
    }

    @Test("Mastered from the grid writes the mark, and a classmate on the closed work shows Reviewing")
    func masteringFromTheGrid() throws {
        let fixture = try makeFixture()
        let shared = CDWorkModel(context: fixture.context)
        shared.lessonID = try #require(fixture.decimal[1].id).uuidString
        shared.status = .active
        shared.createdAt = Date()
        for student in [fixture.ada, fixture.bruno] {
            let participant = CDWorkParticipantEntity(context: fixture.context)
            participant.studentID = student.cloudKitKey
            participant.work = shared
        }
        try fixture.context.save()
        fixture.viewModel.recomputeMatrix(context: fixture.context)
        #expect(fixture.status(fixture.bruno, 1) == .practicing)

        fixture.viewModel.markComplete(student: fixture.ada, lesson: fixture.decimal[1], context: fixture.context)

        #expect(fixture.status(fixture.ada, 1) == .mastered)
        #expect(fixture.status(fixture.bruno, 1) == .reviewing)
        // The incremental refresh read the new mark exactly as a full build does.
        let full = ChecklistMatrixBuilder.buildMatrix(
            students: fixture.viewModel.rosterStudents, lessons: fixture.viewModel.lessons, context: fixture.context
        )
        #expect(fixture.viewModel.matrixStates == full)
    }

    // MARK: - Counts and Words

    @Test("Counts cover only the visible students and lessons")
    func countsFollowFilters() throws {
        let fixture = try makeFixture()
        let all = fixture.viewModel.statusCounts
        #expect(all.total == 4 * 3)
        #expect(all[.mastered] == 2)
        #expect(all[.reviewing] == 1)

        fixture.viewModel.studentFilterIDs = [try #require(fixture.bruno.id)]
        fixture.viewModel.applyFilters()
        let bruno = fixture.viewModel.statusCounts
        #expect(bruno.total == 3)
        #expect(bruno[.mastered] == 1)
        #expect(bruno[.reviewing] == 0)
    }

    @Test("Hover text names the lesson ahead when it blocks")
    func helpText() throws {
        let fixture = try makeFixture()
        let lesson = fixture.decimal[1]
        let preceding = fixture.viewModel.precedingLessonNames[try #require(lesson.id)]
        #expect(preceding == "Decimal 0")

        let blocked = ChecklistCellDescription.helpText(
            studentName: "Dov T", lessonName: lesson.name,
            state: fixture.viewModel.state(for: fixture.dov, lesson: lesson), precedingLessonName: preceding
        )
        #expect(blocked == "Dov T · Decimal 1 — Not yet: Decimal 0 not presented")

        let ready = ChecklistCellDescription.helpText(
            studentName: "Dov T", lessonName: "Decimal 0",
            state: fixture.viewModel.state(for: fixture.dov, lesson: fixture.decimal[0]), precedingLessonName: nil
        )
        #expect(ready == "Dov T · Decimal 0 — Ready")

        let value = ChecklistCellDescription.accessibilityValue(
            state: fixture.viewModel.state(for: fixture.dov, lesson: lesson), precedingLessonName: preceding
        )
        #expect(value == "Not yet ready, Decimal 0 not presented")
    }
}
