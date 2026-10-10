import CoreData
import Foundation

// Complete: the meeting is filed in one save and the form is emptied.
extension MeetingDraftModel {

    /// Files the meeting: history, work reviews, focus changes, requested
    /// lessons to the inbox, today's booking cleared and the next one booked.
    /// Re-present and Ready for Next work changed since the meeting plans
    /// nothing and is named in a toast (bug hunt 2026-10-10, #13). Returns
    /// false (form kept) when the save fails.
    func complete(
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator,
        lessonName: (UUID) -> String?
    ) -> Bool {
        takeUpStored()
        let checklist = FocusItemService.ChecklistChanges(
            resolvedIDs: resolvedFocusIDs, droppedIDs: droppedFocusIDs, newTexts: pendingFocus.map(\.text)
        )
        var completed = data
        completed.isCompleted = true
        // The checklist, then any focus typed on the student record's Meetings tab.
        completed.focusText = checklist.historyText(active: activeFocusItems, typed: readStored().focusText.trimmed())
        completed.requestsText = (requestLessonIDs.compactMap(lessonName) + allRequestTexts).joined(separator: "; ")

        // Everything below lands in one save, or none of it does: a failed
        // save takes back the history entry, reviews and inbox drafts, so
        // trying Complete again doesn't file them twice.
        let transaction = ContextMutationTransaction(context: context)
        guard let meeting = MeetingPersistenceService.saveToHistory(
            studentID: studentID, data: completed, context: context, save: false
        ) else {
            transaction.rollback()
            return false
        }
        let meetingID = meeting.id ?? UUID()

        MeetingReviewService.persistReviews(
            meetingID: meetingID, meeting: meeting, drafts: workNotes, reviewedIDs: reviewedWorkIDs, context: context
        )
        checklist.file(active: activeFocusItems, studentID: studentID, meetingID: meetingID, context: context)
        let filed: MeetingLessonDecisions.Filed
        do {
            filed = try MeetingLessonDecisions.file(data, studentID: studentID, context: context)
        } catch {
            transaction.rollback()
            return false
        }
        MeetingLessonDecisions.fileRequests(
            requestLessonIDs, skipping: filed.planned, studentID: studentID, context: context
        )
        _ = MeetingScheduler.completeBooking(studentID: studentID, heldOn: Date(), context: context)

        // A failure shows the "Couldn't Save" alert and keeps the form open
        // so the meeting record isn't silently lost.
        guard saveCoordinator.save(context, reason: "Save meeting") else {
            transaction.rollback()
            return false
        }
        transaction.commit()
        if let message = MeetingLessonDecisions.changedSinceMessage(filed.changedSince, context: context) {
            ToastService.shared.showInfo(message, duration: 4)
        }

        if let next = nextMeetingDate {
            MeetingScheduler.scheduleMeeting(studentID: studentID, date: next, context: context)
        }
        clear()
        refreshFocusItems(context: context)
        return true
    }
}
