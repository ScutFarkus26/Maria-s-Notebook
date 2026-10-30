import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, Part 1 #10–#16: the Meetings tab's Save to History
// files lesson requests and focus changes, two windows on one child keep each
// other's decisions and receipts, a Clear that can't save keeps the draft,
// Complete leaves alone work changed after the meeting, a rest the meeting
// ended comes back with the take-back, and a decision reaches the stored
// draft at once. The room and helpers are in +LessonDecisions.
extension MeetingDraftStoreTests {

    // MARK: - Save to History (#10)

    @Test("The Meetings tab's Save to History puts requested lessons in the inbox and files focus changes")
    @MainActor
    func tabSaveFilesRequestsAndFocus() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let context = room.context
        let requested = CoreDataTestHelpers.seedLesson(in: context, name: "Clocks", area: "Math", sequence: "Time")
        let earlier = UUID()
        let kept = FocusItemService.create(
            studentID: room.child, text: "Read every day", meetingID: earlier, sortOrder: 0, context: context
        )
        let done = FocusItemService.create(
            studentID: room.child, text: "Finish the map", meetingID: earlier, sortOrder: 1, context: context
        )
        let dropped = FocusItemService.create(
            studentID: room.child, text: "Tidy the shelf", meetingID: earlier, sortOrder: 2, context: context
        )
        #expect(CoreDataTestHelpers.save(context))

        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: context)
        draft.requestLessonIDs = [try #require(requested.id)]
        draft.resolvedFocusIDs = [try #require(done.id)]
        draft.droppedFocusIDs = [try #require(dropped.id)]
        draft.pendingFocus = [PendingFocusItem(text: "Practice cursive")]
        draft.flush()

        var tab = MeetingPersistenceService.CurrentMeetingData()
        tab.reflectionText = "Proud of the map"
        tab.focusText = "Help a younger child"
        #expect(MeetingLessonDecisions.saveTabMeeting(studentID: room.child, tabData: tab, context: context))

        let meeting = try #require(context.safeFetch(CDFetchRequest(CDStudentMeeting.self)).first)
        let meetingID = try #require(meeting.id)
        let inbox = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
            .filter { $0.lessonID == requested.id?.uuidString }
        #expect(inbox.map(\.state) == [.draft])
        #expect(inbox.first?.resolvedStudentIDs == [room.child])
        #expect(done.status == .resolved && done.resolvedInMeetingIDUUID == meetingID)
        #expect(dropped.status == .dropped && dropped.resolvedInMeetingIDUUID == meetingID)
        #expect(kept.status == .active)
        let active = FocusItemService.fetchActive(studentID: room.child, context: context)
        #expect(active.map(\.text) == ["Read every day", "Practice cursive"])
        #expect(active.last?.createdInMeetingIDUUID == meetingID)
        #expect(meeting.focus == "[done] Finish the map\n• Read every day\n• Practice cursive\nHelp a younger child")
        #expect(meeting.requests == "Clocks")
        #expect(!context.hasChanges)
    }

    // MARK: - Two windows on one child (#11)

    @Test("A second window's save keeps a Re-present made in the first, and Complete there plans it")
    @MainActor
    func secondWindowKeepsRepresent() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let workID = try #require(room.work.id)
        let first = MeetingDraftModel(studentID: room.child)
        first.load(context: room.context)
        let second = MeetingDraftModel(studentID: room.child)
        second.load(context: room.context)

        first.represent(room.work, context: room.context)
        first.flush()
        second.reflection = "Typed in the other window"
        second.flush()

        let stored = MeetingPersistenceService.loadCurrent(studentID: room.child)
        #expect(stored.representWorkIDs == [workID.uuidString])
        #expect(stored.closeTokens?[workID.uuidString]?.count == 1)
        #expect(stored.reflectionText == "Typed in the other window")
        #expect(second.representWorkIDs == [workID])

        #expect(second.complete(context: room.context, saveCoordinator: .preview) { _ in nil })
        #expect(openPlans(for: room.first, in: room.context).map(\.resolvedStudentIDs) == [[room.child]])
    }

    @Test("A Re-present switched off in one window doesn't come back from another")
    @MainActor
    func switchedOffRepresentStaysOff() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let workID = try #require(room.work.id)
        let first = MeetingDraftModel(studentID: room.child)
        first.load(context: room.context)
        first.represent(room.work, context: room.context)
        first.flush()
        let second = MeetingDraftModel(studentID: room.child)
        second.load(context: room.context)
        #expect(second.representWorkIDs == [workID])

        #expect(first.decide(room.work, status: .active, context: room.context))
        first.flush()
        second.guideNotes = "Ask about the map"
        second.flush()

        let stored = MeetingPersistenceService.loadCurrent(studentID: room.child)
        #expect((stored.representWorkIDs ?? []).isEmpty)
        #expect((stored.closeTokens ?? [:]).isEmpty)
        #expect(stored.guideNotesText == "Ask about the map")
        #expect(second.representWorkIDs.isEmpty)
        #expect(second.complete(context: room.context, saveCoordinator: .preview) { _ in nil })
        #expect(openPlans(for: room.first, in: room.context).isEmpty)
        #expect(room.work.status == .active)
    }

    @Test("A window with nothing unsaved takes up what another window stored, receipts included")
    @MainActor
    func idleWindowTakesUpTheOther() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let workID = try #require(room.work.id)
        let first = MeetingDraftModel(studentID: room.child)
        first.load(context: room.context)
        let second = MeetingDraftModel(studentID: room.child)
        second.load(context: room.context)

        first.represent(room.work, context: room.context)
        first.reflection = "Proud of the stamp game"
        first.flush()
        // What the open meeting does on the change notice.
        second.storedDraftsChanged()
        #expect(second.representWorkIDs == [workID])
        #expect(second.closeTokens[workID]?.count == 1)
        #expect(second.reflection == "Proud of the stamp game")

        // Keep Working in the second window takes the first window's close back.
        #expect(second.decide(room.work, status: .active, context: room.context))
        try expectAsBeforeTheMeeting(room)
    }

    // MARK: - A Clear that can't save (#12)

    @Test("Clear that can't save the reopened work keeps the draft and its decisions")
    @MainActor
    func failedClearKeepsTheDraft() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let workID = try #require(room.work.id)
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        draft.flush()

        // A row missing a mandatory value, so the next save fails.
        let broken = CDAttendanceRecord(context: room.context)
        broken.date = Date()
        broken.setValue(nil, forKey: "studentID")
        draft.discard(context: room.context)

        #expect(room.work.status == .incomplete)
        #expect(draft.representWorkIDs == [workID])
        #expect(draft.closeTokens[workID]?.count == 1)
        #expect(MeetingPersistenceService.loadCurrent(studentID: room.child).representWorkIDs == [workID.uuidString])

        // Once a save can go through, Clear takes the close back.
        room.context.delete(broken)
        draft.discard(context: room.context)
        try expectAsBeforeTheMeeting(room)
        #expect(!MeetingPersistenceService.hasDraft(studentID: room.child))
    }

    // MARK: - Work changed after the meeting (#13)

    @Test("Complete plans nothing for Re-present work marked Mastered after the meeting")
    @MainActor
    func completeSkipsRepresentChangedSince() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)

        try WorkLogService.log([.init(work: room.work, status: .mastered)], context: room.context)
        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })

        #expect(openPlans(for: room.first, in: room.context).isEmpty)
        #expect(!room.given.needsAnotherPresentation)
        #expect(room.work.status == .mastered)
    }

    @Test("Ready for Next still puts the next lesson On Deck for work changed after the meeting")
    @MainActor
    func completePlansReadyChangedSince() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.decide(room.work, status: .done, context: room.context)
        draft.setReadyForNext(true, for: room.work)

        // Ready for Next never set the status, so a change to it says nothing about readiness.
        try WorkLogService.log([.init(work: room.work, status: .mastered)], context: room.context)
        #expect(draft.complete(context: room.context, saveCoordinator: .preview) { _ in nil })

        #expect(openPlans(for: room.second, in: room.context).map(\.resolvedStudentIDs) == [[room.child]])
        #expect(room.given.confirmedStudentIDs == [room.child.uuidString])
        #expect(room.work.status == .mastered)
    }

    @Test("Complete still plans a Re-present whose work is as the meeting left it")
    @MainActor
    func completePlansUnchangedRepresent() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        draft.flush()

        // After a relaunch, from the stored draft.
        let reopened = MeetingDraftModel(studentID: room.child)
        reopened.load(context: room.context)
        #expect(reopened.complete(context: room.context, saveCoordinator: .preview) { _ in nil })
        #expect(openPlans(for: room.first, in: room.context).map(\.resolvedStudentIDs) == [[room.child]])
    }

    @Test("The message after Complete names the work changed since")
    @MainActor
    func changedSinceMessageNamesTheLesson() throws {
        let room = try makeDecisionRoom()
        #expect(MeetingLessonDecisions.changedSinceMessage([room.work], context: room.context)
            == "Stamp Game was changed after the meeting, so nothing was planned for it.")
        #expect(MeetingLessonDecisions.changedSinceMessage([], context: room.context) == nil)
    }

    // MARK: - Clear's confirmation (#14)

    @Test("Clear's confirmation names the work that goes back, and leaves out work changed since")
    @MainActor
    func clearConfirmationNamesTheWork() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let other = makeWork(for: room.child, from: room.given, lesson: room.second, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        draft.represent(other, context: room.context)
        let stored = MeetingPersistenceService.loadCurrent(studentID: room.child)
        let erased = "Everything written for Ora L's meeting so far will be erased."

        let both = MeetingLessonDecisions.clearConfirmation(studentName: "Ora L", draft: stored, context: room.context)
        #expect(both.hasPrefix(erased + " Dot Board"))
        #expect(both.hasSuffix("Stamp Game go back to how they were before the meeting."))

        try WorkLogService.log([.init(work: other, status: .mastered)], context: room.context)
        #expect(MeetingLessonDecisions.clearConfirmation(studentName: "Ora L", draft: stored, context: room.context)
            == erased + " Stamp Game goes back to how it was before the meeting.")
        #expect(MeetingLessonDecisions.clearConfirmation(studentName: "Ora L", draft: .init(), context: room.context)
            == erased)
    }

    // MARK: - A rest the meeting ended (#15)

    @Test("Re-present on resting work, then Clear after a relaunch, puts the rest back")
    @MainActor
    func clearPutsTheRestBack() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let restUntil = AppCalendar.startOfDay(AppCalendar.addingDays(10, to: Date()))
        room.work.restingUntil = restUntil
        #expect(CoreDataTestHelpers.save(room.context))

        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        #expect(room.work.restingUntil == nil)
        draft.flush()

        let reopened = MeetingDraftModel(studentID: room.child)
        reopened.load(context: room.context)
        reopened.discard(context: room.context)
        #expect(room.work.restingUntil == restUntil)
        try expectAsBeforeTheMeeting(room)
    }

    @Test("Switching choices on resting work keeps the rest to put back")
    @MainActor
    func switchingOutcomesKeepsTheRest() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let restUntil = AppCalendar.startOfDay(AppCalendar.addingDays(10, to: Date()))
        room.work.restingUntil = restUntil
        #expect(CoreDataTestHelpers.save(room.context))

        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        draft.decide(room.work, status: .done, context: room.context)
        draft.represent(room.work, context: room.context)
        #expect(room.work.restingUntil == nil)
        draft.discard(context: room.context)
        #expect(room.work.restingUntil == restUntil)
        try expectAsBeforeTheMeeting(room)
    }

    // MARK: - A decision reaches the draft at once (#16)

    @Test("A card's decision is in the stored draft as soon as the work is saved")
    @MainActor
    func decisionStoredAtOnce() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let workID = try #require(room.work.id).uuidString
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)

        draft.represent(room.work, context: room.context)
        var stored = MeetingPersistenceService.loadCurrent(studentID: room.child)
        #expect(stored.representWorkIDs == [workID])
        #expect(stored.reviewedWorkIDs == [workID])
        #expect(stored.closeTokens?[workID]?.count == 1)

        draft.rest(room.work, until: AppCalendar.addingDays(14, to: Date()), context: room.context)
        stored = MeetingPersistenceService.loadCurrent(studentID: room.child)
        #expect((stored.representWorkIDs ?? []).isEmpty)
        #expect((stored.closeTokens ?? [:]).isEmpty)
        #expect(stored.reviewedWorkIDs == [workID])
    }

    // MARK: - Receipts from older drafts

    @Test("A receipt stored before rests were kept still reads back, with no rest to put back")
    func olderReceiptDecodes() throws {
        let json = """
        {"day":0,"rows":[{"objectURI":"x-coredata://STORE/WorkModel/p1","statusRaw":"active"}],
         "participants":[],"checkIns":[],"completedTodoURIs":[],"createdObjectURIs":[],
         "leftStatusRaw":"incomplete"}
        """
        let token = try JSONDecoder().decode(MeetingCloseToken.self, from: Data(json.utf8))
        #expect(token.leftStatusRaw == "incomplete")
        #expect(token.rows.count == 1)
    }
}
