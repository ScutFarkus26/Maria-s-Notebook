import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The 2026-10-10 fixes' review: Save to History files the workflow's work
// reviews and notes; two windows on one child merge field by field (a note in
// one can't erase the other's decision, nor text the other's text); a
// take-back leaves alone a repeating todo's next copy the guide edited and
// check-ins she changed since. The room and helpers are in +LessonDecisions.
extension MeetingDraftStoreTests {

    // MARK: - Save to History files reviews

    @Test("The Meetings tab's Save to History files the workflow's work reviews and their notes")
    @MainActor
    func tabSaveFilesReviews() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let workID = try #require(room.work.id)
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        #expect(draft.decide(room.work, status: .keepPracticing, context: room.context))
        draft.workNotes[workID] = "Carrying is still slow"
        draft.flush()

        var tab = MeetingPersistenceService.CurrentMeetingData()
        tab.reflectionText = "Proud of the stamp game"
        #expect(MeetingLessonDecisions.saveTabMeeting(studentID: room.child, tabData: tab, context: room.context))

        let meeting = try #require(room.context.safeFetch(CDFetchRequest(CDStudentMeeting.self)).first)
        let reviews = MeetingReviewService.fetchReviews(meetingID: try #require(meeting.id), context: room.context)
        #expect(reviews.map(\.workIDUUID) == [workID])
        #expect(reviews.first?.noteText == "Carrying is still slow")
        #expect(!room.context.hasChanges)
    }

    @Test("The Meetings tab's save writes only what it changed, so it can't write back the window's text")
    func tabSaveWritesOnlyItsChanges() throws {
        let name = "MeetingDraftStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let child = UUID()
        var start = MeetingPersistenceService.CurrentMeetingData()
        start.reflectionText = "Proud of the map"
        start.guideNotesText = "Ask about the map"
        start.reviewedWorkIDs = [UUID().uuidString]
        MeetingPersistenceService.saveCurrent(studentID: child, data: start, defaults: defaults)

        // The tab shows what it loaded; the Meetings window then changes the reflection.
        let loaded = MeetingPersistenceService.loadCurrent(studentID: child, defaults: defaults)
        var tabBase = MeetingPersistenceService.CurrentMeetingData()
        tabBase.reflectionText = loaded.reflectionText
        tabBase.guideNotesText = loaded.guideNotesText
        var window = loaded
        window.reflectionText = "Proud of the map and the timeline"
        MeetingPersistenceService.saveCurrent(studentID: child, data: window, defaults: defaults)

        var tab = tabBase
        tab.guideNotesText = "Ask about the timeline"
        MeetingPersistenceService.saveTabFields(studentID: child, data: tab, base: tabBase, defaults: defaults)

        let stored = MeetingPersistenceService.loadCurrent(studentID: child, defaults: defaults)
        #expect(stored.reflectionText == "Proud of the map and the timeline")
        #expect(stored.guideNotesText == "Ask about the timeline")
        #expect(stored.reviewedWorkIDs == start.reviewedWorkIDs)
    }

    // MARK: - Two windows merge field by field

    @Test("A note typed in one window doesn't erase a Re-present made in the other")
    @MainActor
    func noteDoesNotEraseOtherWindowsDecision() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let workID = try #require(room.work.id)
        let first = MeetingDraftModel(studentID: room.child)
        first.load(context: room.context)
        let second = MeetingDraftModel(studentID: room.child)
        second.load(context: room.context)

        second.workNotes[workID] = "Ask about borrowing"
        first.represent(room.work, context: room.context)
        second.flush()

        let stored = MeetingPersistenceService.loadCurrent(studentID: room.child)
        #expect(stored.representWorkIDs == [workID.uuidString])
        #expect(stored.closeTokens?[workID.uuidString]?.count == 1)
        #expect(stored.reviewedWorkIDs == [workID.uuidString])
        #expect(stored.workReviewDrafts?[workID.uuidString] == "Ask about borrowing")
        #expect(second.representWorkIDs == [workID])
        #expect(second.closeTokens[workID]?.count == 1)
    }

    @Test("Each window's text, requests and focus ticks survive the other's save")
    @MainActor
    func textMergesByField() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let focus = FocusItemService.create(
            studentID: room.child, text: "Read every day", meetingID: UUID(), sortOrder: 0, context: room.context
        )
        #expect(CoreDataTestHelpers.save(room.context))
        let focusID = try #require(focus.id)
        let first = MeetingDraftModel(studentID: room.child)
        first.load(context: room.context)
        let second = MeetingDraftModel(studentID: room.child)
        second.load(context: room.context)

        first.reflection = "Typed in the first window"
        second.guideNotes = "Typed in the second window"
        second.requestTexts = ["Clocks"]
        second.resolvedFocusIDs = [focusID]
        second.nextMeetingDate = AppCalendar.startOfDay(AppCalendar.addingDays(7, to: Date()))
        second.flush()
        first.flush()

        let stored = MeetingPersistenceService.loadCurrent(studentID: room.child)
        #expect(stored.reflectionText == "Typed in the first window")
        #expect(stored.guideNotesText == "Typed in the second window")
        #expect(stored.requestsText == "Clocks")
        #expect(stored.resolvedFocusIDs == [focusID.uuidString])
        #expect(stored.nextMeetingDate == second.nextMeetingDate)
        #expect(first.guideNotes == "Typed in the second window")
    }

    // MARK: - A take-back leaves later changes alone

    @Test("Clear keeps a repeating todo's next copy the guide edited, and still reopens the todo")
    @MainActor
    func takeBackKeepsAnEditedTodoCopy() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        room.todo.recurrence = .daily
        #expect(CoreDataTestHelpers.save(room.context))
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)

        #expect(room.todo.isCompleted)
        let copy = try #require(openCopies(of: room.todo, in: room.context).first)
        copy.notes = "Bring the bead frame"
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(draft.discard(context: room.context))
        #expect(!room.todo.isCompleted)
        #expect(!copy.isDeleted && copy.managedObjectContext != nil)
        #expect(openCopies(of: room.todo, in: room.context) == [copy])
        #expect(room.work.status == .active)
    }

    @Test("Clear still removes a repeating todo's next copy nobody touched")
    @MainActor
    func takeBackRemovesAnUntouchedTodoCopy() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        room.todo.recurrence = .daily
        #expect(CoreDataTestHelpers.save(room.context))
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        #expect(openCopies(of: room.todo, in: room.context).count == 1)

        #expect(draft.discard(context: room.context))
        #expect(openCopies(of: room.todo, in: room.context).isEmpty)
        try expectAsBeforeTheMeeting(room)
    }

    @Test("Clear leaves a check-in the guide moved or marked since, and puts the others back")
    @MainActor
    func takeBackLeavesChangedCheckIns() throws {
        let room = try makeDecisionRoom()
        defer { MeetingPersistenceService.clearCurrent(studentID: room.child) }
        let extra = CDWorkCheckIn.make(
            for: room.work, on: AppCalendar.addingDays(10, to: AppCalendar.startOfDay(Date())),
            purpose: "progressCheck", in: room.context
        )
        #expect(CoreDataTestHelpers.save(room.context))
        let draft = MeetingDraftModel(studentID: room.child)
        draft.load(context: room.context)
        draft.represent(room.work, context: room.context)
        #expect(room.laterCheckIn.status == .skipped)
        #expect(extra.status == .skipped)

        // Moved to another day, and marked done, after the meeting.
        let moved = AppCalendar.addingDays(21, to: AppCalendar.startOfDay(Date()))
        room.laterCheckIn.date = moved
        extra.status = .completed
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(draft.discard(context: room.context))
        #expect(room.work.status == .active)
        #expect(room.todaysCheckIn.status == .scheduled)
        #expect(room.laterCheckIn.date == moved)
        #expect(room.laterCheckIn.status == .skipped)
        #expect(extra.status == .completed)
    }

    /// The open todos of `todo`'s repeat other than `todo` itself.
    @MainActor
    func openCopies(of todo: CDTodoItem, in context: NSManagedObjectContext) -> [CDTodoItem] {
        context.safeFetch(CDFetchRequest(CDTodoItem.self))
            .filter { $0 !== todo && !$0.isDeleted && !$0.isCompleted && $0.title == todo.title }
    }
}
