import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

@Suite("Presentation Session Commit")
@MainActor
struct PresentationSessionCommitTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let coordinator: SaveCoordinator
        let lesson: CDLesson
        let nextLesson: CDLesson
        let ada: CDStudent
        let ben: CDStudent
        let assignment: CDLessonAssignment
        let presentedDay: Date
    }

    private func makeFixture(absent: [Int] = []) throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads: Addition", area: "Math", sequence: "Decimal System"
        )
        lesson.orderInSequence = 1
        let nextLesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads: Subtraction", area: "Math", sequence: "Decimal System"
        )
        nextLesson.orderInSequence = 2
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        let presentedDay = AppCalendar.startOfDay(Date())
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada, ben], scheduledFor: presentedDay, context: context
        )
        try context.save()
        return Fixture(
            context: context, coordinator: coordinator, lesson: lesson, nextLesson: nextLesson,
            ada: ada, ben: ben, assignment: assignment, presentedDay: presentedDay
        )
    }

    private func ids(_ fixture: Fixture) throws -> (UUID, UUID) {
        (try #require(fixture.ada.id), try #require(fixture.ben.id))
    }

    private func record(_ fixture: Fixture) throws {
        _ = try ImmediatePresentationRecordingService.record(
            assignment: fixture.assignment,
            presentedOn: fixture.presentedDay,
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )
    }

    @discardableResult
    private func commit(
        _ fixture: Fixture,
        decisions: [UUID: CaptureFollowUp],
        all: [UUID: CaptureFollowUp]? = nil,
        notes: [UUID: String] = [:],
        groupNote: String = "",
        checkIn: PresentationCheckIn = .nextWorkCycle
    ) throws -> PresentationSessionCommit.Receipt {
        let (ada, ben) = try ids(fixture)
        return try PresentationSessionCommit.apply(
            PresentationSessionCommit.Input(
                assignment: fixture.assignment,
                lesson: fixture.lesson,
                studentIDs: [ada, ben],
                groupNote: groupNote,
                childNotes: notes,
                decisions: decisions,
                allDecisions: all ?? decisions,
                checkIn: checkIn,
                lessons: [fixture.lesson, fixture.nextLesson]
            ),
            context: fixture.context,
            saveCoordinator: fixture.coordinator
        )
    }

    private func rows(_ fixture: Fixture) throws -> [String: CDLessonPresentation] {
        let id = try #require(fixture.assignment.id)
        return Dictionary(
            PresentationFollowUpService.rows(for: id, in: fixture.context).map { ($0.studentID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func work(_ fixture: Fixture) throws -> [CDWorkModel] {
        let id = try #require(fixture.assignment.id)
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID == %@", id.uuidString)
        return fixture.context.safeFetch(request)
    }

    @Test("Practice with a day gives each child work, a check-in that day, and an open check-work row")
    func practiceWithCheckIn() throws {
        let fixture = try makeFixture()
        try record(fixture)
        let (ada, ben) = try ids(fixture)
        let monday = AppCalendar.shared.date(byAdding: .day, value: 5, to: fixture.presentedDay) ?? fixture.presentedDay

        let receipt = try commit(fixture, decisions: [ada: .practice, ben: .practice], checkIn: .on(monday))

        let works = try work(fixture)
        #expect(works.count == 2)
        #expect(works.allSatisfy { $0.kind == .practiceLesson })
        #expect(receipt.checkInCount == 2)
        #expect(receipt.createdWorkIDs.count == 2)
        for work in works {
            let checkIns = WorkDeletionService.checkIns(of: work, in: fixture.context)
            #expect(checkIns.contains { AppCalendar.shared.isDate($0.date ?? .distantPast, inSameDayAs: monday) })
        }
        let rows = try rows(fixture)
        #expect(rows.values.allSatisfy { $0.hasOpenFollowUp && $0.followUpAction == .checkWork })
        #expect(rows.values.allSatisfy { $0.followUpReviewAt == AppCalendar.startOfDay(monday) })
    }

    @Test("Re-present closes the child's row and puts the lesson On Deck for her alone")
    func representForOneChild() throws {
        let fixture = try makeFixture()
        try record(fixture)
        let (ada, ben) = try ids(fixture)

        try commit(
            fixture,
            decisions: [ben: .represent],
            all: [ada: .continueObserving, ben: .represent]
        )

        let rows = try rows(fixture)
        #expect(rows[ben.uuidString]?.followUpResolution == .supportOrRepresent)
        #expect(rows[ada.uuidString]?.hasOpenFollowUp == true)
        let lessonID = try #require(fixture.lesson.id)
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        let drafts = fixture.context.safeFetch(request).filter { !$0.isPresented }
        #expect(drafts.count == 1)
        #expect(drafts.first?.resolvedStudentIDs == [ben])
        #expect(try work(fixture).isEmpty)
    }

    @Test("Ready for next confirms the child and plans the next lesson once")
    func readyForNextPlansNextLesson() throws {
        let fixture = try makeFixture()
        try record(fixture)
        let (ada, ben) = try ids(fixture)

        let receipt = try commit(fixture, decisions: [ada: .readyForNextLesson, ben: .readyForNextLesson])
        #expect(receipt.nextLessonPlanned)
        #expect(fixture.assignment.isStudentConfirmed(ada))

        let nextID = try #require(fixture.nextLesson.id)
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", nextID.uuidString)
        #expect(fixture.context.safeFetch(request).count == 1)

        // A second Done for the same children plans nothing more.
        let again = try commit(fixture, decisions: [ada: .readyForNextLesson])
        #expect(!again.nextLessonPlanned)
        #expect(fixture.context.safeFetch(request).count == 1)
    }

    @Test("Notes are filed per child, and keep watching with no note writes no empty note")
    func notesAndKeepWatching() throws {
        let fixture = try makeFixture()
        try record(fixture)
        let (ada, ben) = try ids(fixture)

        let receipt = try commit(
            fixture,
            decisions: [:],
            all: [ada: .continueObserving, ben: .continueObserving],
            notes: [ada: "Exchanged the tens confidently."]
        )
        #expect(receipt.noteCount == 1)
        let notes = (fixture.assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []
        #expect(notes.count == 1)
        #expect(notes.allSatisfy { !$0.body.trimmed().isEmpty })
    }

    @Test("Moving off Practice takes back the untouched practice work, and only that")
    func changedDecisionRetiresUntouchedWork() throws {
        let fixture = try makeFixture()
        try record(fixture)
        let (ada, ben) = try ids(fixture)
        let presentationID = try #require(fixture.assignment.id)
        try commit(fixture, decisions: [ada: .practice, ben: .practice], checkIn: .on(fixture.presentedDay))

        // Ben has already had his check-in, so his practice is his record now.
        let bensWork = try #require(try work(fixture).first { $0.studentID == ben.uuidString })
        let bensCheckIn = try #require(WorkDeletionService.checkIns(of: bensWork, in: fixture.context).first)
        bensCheckIn.status = .completed
        try fixture.context.save()

        try commit(fixture, decisions: [ada: .continueObserving, ben: .continueObserving])

        let works = try work(fixture)
        #expect(works.count == 1)
        #expect(works.first?.studentID == ben.uuidString)
        let state = PresentationSession.appliedState(presentationID: presentationID, in: fixture.context)
        #expect(state.decisions[ada] == .continueObserving)
    }

    @Test("Practice changed to Follow-up leaves one open work item, the follow-up")
    func practiceToFollowUpReplacesWork() throws {
        let fixture = try makeFixture()
        try record(fixture)
        let (ada, ben) = try ids(fixture)
        let day = PresentationCheckIn.on(fixture.presentedDay)
        try commit(
            fixture, decisions: [ada: .practice], all: [ada: .practice, ben: .continueObserving], checkIn: day
        )

        // A check-in still only scheduled is not progress: the practice goes.
        let receipt = try commit(
            fixture, decisions: [ada: .followUpWork], all: [ada: .followUpWork, ben: .continueObserving], checkIn: day
        )

        let works = try work(fixture)
        #expect(works.map(\.kind) == [.followUpAssignment])
        #expect(receipt.checkInCount == 1)
    }

    @Test("A child added in Details is saved onto the record before How It Went gives her work")
    func addedChildLandsBeforeHowItWent() throws {
        let fixture = try makeFixture()
        try record(fixture)
        let (ada, ben) = try ids(fixture)
        let cy = CoreDataTestHelpers.seedStudent(in: fixture.context, firstName: "Cy")
        let cyID = try #require(cy.id)
        try fixture.context.save()

        let viewModel = PresentationDetailViewModel(
            lessonAssignment: fixture.assignment, viewContext: fixture.context, saveCoordinator: fixture.coordinator
        )
        #expect(!viewModel.hasUnsavedRosterOrLesson)
        viewModel.selectedStudentIDs.insert(cyID)
        #expect(viewModel.hasUnsavedRosterOrLesson)

        // What How It Went… now does first.
        viewModel.save(
            studentsAll: [fixture.ada, fixture.ben, cy], lessons: [fixture.lesson],
            lessonAssignmentsAll: [fixture.assignment], calendar: AppCalendar.shared
        )
        #expect(!viewModel.hasUnsavedRosterOrLesson)

        let receipt = try PresentationSessionCommit.apply(
            PresentationSessionCommit.Input(
                assignment: fixture.assignment, lesson: fixture.lesson, studentIDs: [ada, ben, cyID],
                groupNote: "", childNotes: [cyID: "Carried the tens tray."],
                decisions: [cyID: .practice],
                allDecisions: [ada: .continueObserving, ben: .continueObserving, cyID: .practice],
                checkIn: .nextWorkCycle, lessons: [fixture.lesson, fixture.nextLesson]
            ),
            context: fixture.context, saveCoordinator: fixture.coordinator
        )
        #expect(receipt.noteCount == 1)
        #expect(try work(fixture).map(\.studentID) == [cyID.uuidString])
        #expect(try rows(fixture)[cyID.uuidString] != nil)
    }

    @Test("Reading the record back gives each child's standing decision")
    func appliedStateRoundTrip() throws {
        let fixture = try makeFixture()
        try record(fixture)
        let (ada, ben) = try ids(fixture)
        let presentationID = try #require(fixture.assignment.id)

        try commit(fixture, decisions: [ada: .practice, ben: .represent])

        let state = PresentationSession.appliedState(presentationID: presentationID, in: fixture.context)
        #expect(state.decisions[ada] == .practice)
        #expect(state.decisions[ben] == .represent)

        // Reopened, the session shows them as they stand and nothing is pending.
        let session = PresentationSession(presentationID: presentationID)
        let defaults = try #require(UserDefaults(suiteName: "PresentationSessionCommitTests.\(UUID().uuidString)"))
        session.loadDecisions(
            studentIDs: [ada, ben], defaultDecision: .continueObserving,
            context: fixture.context, defaults: defaults
        )
        #expect(session.decision(for: ada) == .practice)
        #expect(session.decision(for: ben) == .represent)
        #expect(session.pendingDecisions(for: [ada, ben]).isEmpty)
    }
}
