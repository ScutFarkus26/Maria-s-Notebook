import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Re-present and Ready for Next take effect at the tap (domain logic review
// 2026-11-20, R8; Decision 6): the lesson is planned the moment the card is
// tapped, saved for every device, and taken back through the card's
// `MeetingTapPlan` receipt. Complete has nothing left to carry out. The
// room and helpers are in +LessonDecisions.
extension MeetingDraftStoreTests {

    /// What another device sees once the tap's save has synced: a fresh
    /// context on the same store, with nothing of this one's in memory.
    @MainActor
    private func plansSeenElsewhere(for lesson: CDLesson, in room: DecisionRoom) -> [[UUID]] {
        let elsewhere = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        elsewhere.persistentStoreCoordinator = room.context.persistentStoreCoordinator
        return elsewhere.safeFetch(CDFetchRequest(CDLessonAssignment.self))
            .filter { !$0.isPresented && $0.lessonID == lesson.id?.uuidString }
            .map(\.resolvedStudentIDs)
    }

    @Test("Re-present on one device plans the lesson again at the tap, with no Complete")
    @MainActor
    func representPlansAtTheTap() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)

        draft.represent(room.work, context: room.context)

        #expect(!room.context.hasChanges)
        #expect(plansSeenElsewhere(for: room.first, in: room) == [[room.child]])
        #expect(room.given.needsAnotherPresentation)
        #expect(room.work.status == .incomplete)
    }

    @Test("Complete after a Re-present plans nothing more")
    @MainActor
    func completeAfterRepresentPlansNothingMore() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)

        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })
        #expect(openPlans(for: room.first, in: room.context).map(\.resolvedStudentIDs) == [[room.child]])
    }

    @Test("Work marked Mastered after a Re-present keeps the plan the tap made")
    @MainActor
    func masteredAfterRepresentKeepsThePlan() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)

        try WorkLogService.log([.init(work: room.work, status: .mastered)], context: room.context)
        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })
        #expect(openPlans(for: room.first, in: room.context).map(\.resolvedStudentIDs) == [[room.child]])
        #expect(room.work.status == .mastered)
    }

    @Test("Complete still plans the Re-present in a draft stored before plans were made at the tap")
    @MainActor
    func completePlansAnOlderDraftsRepresent() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        try WorkLogService.log([.init(work: room.work, status: .incomplete)], context: room.context)
        var older = MeetingPersistenceService.CurrentMeetingData()
        older.representWorkIDs = [try #require(room.work.id).uuidString]
        MeetingPersistenceService.saveCurrent(studentID: room.child, data: older)
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        #expect(openPlans(for: room.first, in: room.context).isEmpty)

        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })
        #expect(openPlans(for: room.first, in: room.context).map(\.resolvedStudentIDs) == [[room.child]])
        #expect(room.given.needsAnotherPresentation)
    }

    @Test("Clear takes back the lesson Re-present planned, and the work goes back as it was")
    @MainActor
    func clearTakesBackTheRepresentPlan() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        #expect(openPlans(for: room.first, in: room.context).count == 1)

        draft.discard(context: room.context)
        #expect(openPlans(for: room.first, in: room.context).isEmpty)
        #expect(!room.given.needsAnotherPresentation)
        try expectAsBeforeTheMeeting(room)
    }

    @Test("Another choice after Re-present takes its plan back")
    @MainActor
    func anotherChoiceTakesBackTheRepresentPlan() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)

        draft.decide(room.work, status: .active, context: room.context)
        #expect(openPlans(for: room.first, in: room.context).isEmpty)
        #expect(!room.given.needsAnotherPresentation)
        #expect(!room.context.hasChanges)
    }

    @Test("Ready for Next puts the next lesson On Deck at the tap, and switching it off takes it back")
    @MainActor
    func readyPlansAtTheTap() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)

        draft.setReadyForNext(true, for: room.work)
        #expect(plansSeenElsewhere(for: room.second, in: room) == [[room.child]])
        #expect(room.work.status == .active)

        draft.setReadyForNext(false, for: room.work)
        #expect(plansSeenElsewhere(for: room.second, in: room).isEmpty)
        #expect(!room.context.hasChanges)
    }

    @Test("Switching Ready for Next off leaves a next lesson scheduled since")
    @MainActor
    func readyOffLeavesAScheduledPlan() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.setReadyForNext(true, for: room.work)
        let plan = try #require(openPlans(for: room.second, in: room.context).first)
        plan.schedule(for: AppCalendar.addingDays(3, to: Date()), using: AppCalendar.shared)
        #expect(CoreDataTestHelpers.save(room.context))

        draft.setReadyForNext(false, for: room.work)
        #expect(!plan.isDeleted)
        #expect(openPlans(for: room.second, in: room.context).count == 1)
        #expect(draft.readyWorkIDs.isEmpty)
    }
}
