import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Re-present and Ready for Next (bug hunt 2026-10-09, #8–#13): a card's
// close is taken back through its stored receipt (Clear, Rest, another
// outcome, after a relaunch, from the student record's tab), work changed
// after the meeting is left alone, and filing plans only what she hasn't had.
extension MeetingDraftStoreTests {

    /// One child, a two-lesson sequence, the first given to her alone, and
    /// her work from it with a check-in today and next week and a linked todo.
    struct DecisionRoom {
        let context: NSManagedObjectContext
        let student: CDStudent
        let child: UUID
        let first: CDLesson
        let second: CDLesson
        let given: CDLessonAssignment
        let work: CDWorkModel
        let todaysCheckIn: CDWorkCheckIn
        let laterCheckIn: CDWorkCheckIn
        let todo: CDTodoItem
    }

    @MainActor
    func makeDecisionRoom() throws -> DecisionRoom {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game", area: "Math", sequence: "Operation")
        first.orderInSequence = 1
        let second = CoreDataTestHelpers.seedLesson(in: context, name: "Dot Board", area: "Math", sequence: "Operation")
        second.orderInSequence = 2
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let child = try #require(student.id)
        let given = PresentationFactory.makePresented(lesson: first, students: [student], context: context)
        let work = makeWork(for: child, from: given, lesson: first, in: context)
        let today = AppCalendar.startOfDay(Date())
        let todaysCheckIn = CDWorkCheckIn.make(for: work, on: today, purpose: "progressCheck", in: context)
        let laterCheckIn = CDWorkCheckIn.make(
            for: work, on: AppCalendar.addingDays(7, to: today), purpose: "progressCheck", in: context
        )
        let todo = CDTodoItem(context: context)
        todo.title = "Check the stamp game"
        todo.linkedWorkItemID = work.id?.uuidString
        #expect(CoreDataTestHelpers.save(context))
        return DecisionRoom(
            context: context, student: student, child: child, first: first, second: second, given: given,
            work: work, todaysCheckIn: todaysCheckIn, laterCheckIn: laterCheckIn, todo: todo
        )
    }

    @MainActor
    func makeWork(
        for child: UUID, from presentation: CDLessonAssignment, lesson: CDLesson, in context: NSManagedObjectContext
    ) -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: lesson.name, studentID: child, lessonID: lesson.id ?? UUID()
        )
        work.presentationID = presentation.id?.uuidString
        return work
    }

    @MainActor
    func completionRecords(_ work: CDWorkModel, in context: NSManagedObjectContext) throws -> [CDWorkCompletionRecord] {
        try WorkCompletionService.records(for: try #require(work.id), in: context)
    }

    @MainActor
    func openPlans(for lesson: CDLesson, in context: NSManagedObjectContext) -> [CDLessonAssignment] {
        context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
            .filter { !$0.isPresented && $0.lessonID == lesson.id?.uuidString }
    }

    /// The work, its check-ins and its todo as they were before the meeting.
    @MainActor
    func expectAsBeforeTheMeeting(_ room: DecisionRoom) throws {
        #expect(room.work.status == .active)
        #expect(room.work.completedAt == nil)
        #expect(room.todaysCheckIn.status == .scheduled)
        #expect(room.laterCheckIn.status == .scheduled)
        #expect(!room.todo.isCompleted)
        #expect(try completionRecords(room.work, in: room.context).isEmpty)
        #expect(!room.context.hasChanges)
    }

    // MARK: - Taking a close back (#9, #10)

    @Test("Keep Working after Re-present takes the close back: check-ins, todo and completion record")
    @MainActor
    func keepWorkingTakesTheCloseBack() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)

        draft.represent(room.work, context: room.context)
        #expect(room.work.status == .incomplete)
        #expect(room.laterCheckIn.status == .skipped)
        #expect(room.todo.isCompleted)
        #expect(try completionRecords(room.work, in: room.context).count == 1)
        #expect(draft.closeTokens[try #require(room.work.id)]?.count == 1)

        #expect(draft.decide(room.work, status: .active, context: room.context))
        try expectAsBeforeTheMeeting(room)
        #expect(draft.representWorkIDs.isEmpty)
        #expect(draft.closeTokens.isEmpty)
        #expect(draft.reviewedWorkIDs.contains(try #require(room.work.id)))
    }

    @Test("Re-present, then Ready for Next, then Clear puts the work back as it was")
    @MainActor
    func representReadyClear() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)

        draft.represent(room.work, context: room.context)
        draft.readyForNext(room.work, context: room.context)
        #expect(room.work.status == .done)
        // Ready replaced Re-present: one close, not two.
        #expect(try completionRecords(room.work, in: room.context).count == 1)
        #expect(draft.closeTokens[try #require(room.work.id)]?.count == 1)

        draft.discard(context: room.context)
        try expectAsBeforeTheMeeting(room)
        #expect(MeetingPersistenceService.loadCurrent(studentID: room.child).isEmpty)
    }

    @Test("Clear after the app reopens takes the closes back through the receipts kept with the draft")
    @MainActor
    func clearAfterRelaunch() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let other = makeWork(for: room.child, from: room.given, lesson: room.first, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        draft.readyForNext(other, context: room.context)
        draft.flush()

        // Only the stored draft is left after a relaunch.
        #expect(MeetingPersistenceService.loadCurrent(studentID: room.child).closeTokens?.count == 2)
        let reopened = MeetingDraftModel(studentID: room.child)
        reopened.load(context: room.context)
        #expect(reopened.closeTokens.count == 2)
        reopened.discard(context: room.context)

        try expectAsBeforeTheMeeting(room)
        #expect(other.status == .active)
        #expect(try completionRecords(other, in: room.context).isEmpty)
    }

    @Test("Rest after Ready for Next reopens the work instead of resting it closed")
    @MainActor
    func restAfterReadyReopens() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.readyForNext(room.work, context: room.context)

        draft.rest(room.work, until: AppCalendar.addingDays(14, to: Date()), context: room.context)
        #expect(room.work.status == .active)
        #expect(room.work.restingUntil != nil)
        #expect(room.laterCheckIn.status == .scheduled)
        #expect(try completionRecords(room.work, in: room.context).isEmpty)
        #expect(draft.readyWorkIDs.isEmpty)
        #expect(draft.closeTokens.isEmpty)
        #expect(!room.context.hasChanges)
    }

    @Test("Rest after Re-present from a draft with no receipts still reopens the work")
    @MainActor
    func restWithoutReceiptReopens() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        try WorkLogService.log([.init(work: room.work, status: .incomplete)], context: room.context)
        var older = MeetingPersistenceService.CurrentMeetingData()
        older.representWorkIDs = [try #require(room.work.id).uuidString]
        MeetingPersistenceService.saveCurrent(studentID: room.child, data: older)

        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.rest(room.work, until: AppCalendar.addingDays(14, to: Date()), context: room.context)
        #expect(room.work.status == .active)
        #expect(draft.representWorkIDs.isEmpty)
    }

    @Test("Work changed after the meeting is left as it is, and the message names its lesson")
    @MainActor
    func changedWorkIsLeftAlone() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)

        // Logged Mastered somewhere else after the meeting.
        try WorkLogService.log([.init(work: room.work, status: .mastered)], context: room.context)
        draft.discard(context: room.context)

        #expect(room.work.status == .mastered)
        #expect(room.laterCheckIn.status == .skipped)
        #expect(MeetingLessonDecisions.leftAloneMessage([room.work], context: room.context)
            == "Stamp Game was changed after the meeting, so it was left as it is.")
    }

    @Test("A draft saved before receipts were kept still puts Re-present work back to Working")
    @MainActor
    func olderDraftReopens() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        try WorkLogService.log([.init(work: room.work, status: .incomplete)], context: room.context)
        var older = MeetingPersistenceService.CurrentMeetingData()
        older.representWorkIDs = [try #require(room.work.id).uuidString]

        MeetingLessonDecisions.takeBack(older, context: room.context)
        #expect(room.work.status == .active)
        #expect(!room.context.hasChanges)
    }

    // MARK: - The student record's Meetings tab (#8)

    @Test("The Meetings tab's Clear takes back the closes the workflow left in the draft")
    @MainActor
    func tabClearTakesBack() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        draft.flush()

        // What the tab's Clear does with the stored draft.
        let stored = MeetingPersistenceService.loadCurrent(studentID: room.child)
        MeetingLessonDecisions.takeBack(stored, context: room.context)
        try expectAsBeforeTheMeeting(room)
    }

    @Test("A meeting open elsewhere drops a draft the tab cleared, so it can't write the decisions back")
    @MainActor
    func openMeetingDropsAClearedDraft() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        draft.flush()

        // Another child's draft changing leaves this one alone.
        draft.storedDraftsChanged()
        #expect(draft.representWorkIDs.count == 1)

        // The tab's Clear, then the change notice the open meeting receives.
        let stored = MeetingPersistenceService.loadCurrent(studentID: room.child)
        MeetingLessonDecisions.takeBack(stored, context: room.context)
        MeetingPersistenceService.clearCurrent(studentID: room.child)
        #expect(!MeetingPersistenceService.hasDraft(studentID: room.child))
        draft.storedDraftsChanged()

        #expect(draft.representWorkIDs.isEmpty && draft.closeTokens.isEmpty && draft.reviewedWorkIDs.isEmpty)
        draft.reflection = "Back to it"
        draft.flush()
        let rewritten = MeetingPersistenceService.loadCurrent(studentID: room.child)
        #expect(rewritten.reflectionText == "Back to it")
        let representIDs = rewritten.representWorkIDs ?? []
        let receipts = rewritten.closeTokens ?? [:]
        #expect(representIDs.isEmpty && receipts.isEmpty)
        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })
        #expect(openPlans(for: room.first, in: room.context).isEmpty)
        try expectAsBeforeTheMeeting(room)
    }

    @Test("The Meetings tab's Save to History plans Re-present and Ready for Next, and files nothing else")
    @MainActor
    func tabSaveFilesDecisions() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let other = makeWork(for: room.child, from: room.given, lesson: room.first, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        draft.readyForNext(other, context: room.context)
        draft.flush()

        var tab = MeetingPersistenceService.CurrentMeetingData()
        tab.reflectionText = "Proud of the stamp game"
        #expect(MeetingLessonDecisions.saveTabMeeting(studentID: room.child, tabData: tab, context: room.context))

        let meeting = try #require(room.context.safeFetch(CDFetchRequest(CDStudentMeeting.self)).first)
        #expect(meeting.reflection == "Proud of the stamp game")
        #expect(openPlans(for: room.first, in: room.context).map(\.resolvedStudentIDs) == [[room.child]])
        #expect(openPlans(for: room.second, in: room.context).map(\.resolvedStudentIDs) == [[room.child]])
        #expect(room.given.needsAnotherPresentation)
        // Reviews are Complete's; the tab files the two lists only.
        #expect(room.context.safeFetch(CDFetchRequest(CDMeetingWorkReview.self)).isEmpty)
        #expect(!room.context.hasChanges)
    }
}
