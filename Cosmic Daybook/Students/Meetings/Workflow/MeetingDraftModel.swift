import Foundation
import CoreData

/// A pending focus item that hasn't been persisted yet (created during this meeting session).
struct PendingFocusItem: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

/// One child's meeting in progress: the form, the focus checklist, the work
/// decisions and the lesson requests. The header, decision cards, form and
/// footer all read this one object, so a layout switch (a window resized
/// across the wide/narrow line) rebuilds views without losing anything.
///
/// Drafts are saved on a short debounce after the last change and flushed
/// when the meeting is left, then removed when it is completed or cleared.
@Observable @MainActor
final class MeetingDraftModel {
    let studentID: UUID

    var reflection = "" { didSet { changed() } }
    var guideNotes = "" { didSet { changed() } }
    /// Catalog lessons asked for; they go to the inbox on Complete.
    var requestLessonIDs: [UUID] = [] { didSet { changed() } }
    /// Requests that matched no lesson, kept as the guide typed them.
    var requestTexts: [String] = [] { didSet { changed() } }
    /// What is typed in the request field and not yet added. Saved with the
    /// draft as a free-text request, and filed as one on Complete, so moving
    /// on doesn't drop it.
    var requestQuery = "" { didSet { changed() } }
    var nextMeetingDate: Date? { didSet { changed() } }

    var pendingFocus: [PendingFocusItem] = [] { didSet { changed() } }
    var resolvedFocusIDs: Set<UUID> = [] { didSet { changed() } }
    var droppedFocusIDs: Set<UUID> = [] { didSet { changed() } }

    var workNotes: [UUID: String] = [:] { didSet { changed() } }
    var reviewedWorkIDs: Set<UUID> = [] { didSet { changed() } }
    /// Work decided as Re-present: closed as Incomplete now, its lesson
    /// planned again as a second pass on Complete.
    var representWorkIDs: Set<UUID> = [] { didSet { changed() } }
    /// Work decided as Ready for Next: closed now with no mastery mark, its
    /// next lesson put On Deck on Complete.
    var readyWorkIDs: Set<UUID> = [] { didSet { changed() } }
    /// The `WorkLogService` receipt of the status each card's choice set,
    /// kept with the draft so Clear, Rest or another outcome can take the
    /// close back after a relaunch, not just log Working on top of it
    /// (bug hunt 2026-10-09, #9 and #10). A list, oldest first, read newest
    /// first; a card's next choice takes the earlier one back, so it rarely
    /// holds more than one.
    var closeTokens: [UUID: [MeetingCloseToken]] = [:] { didSet { changed() } }

    /// Focus items carried from earlier meetings.
    private(set) var activeFocusItems: [CDStudentFocusItem] = []
    /// When the draft last reached disk; nil until something is written.
    private(set) var savedAt: Date?
    /// Lessons with a next lesson in their sequence, worked out once when the
    /// draft loads, so a card's Ready for Next reads a set rather than the
    /// catalog (bug hunt 2026-10-09, #13).
    private(set) var lessonsWithNext: Set<UUID> = []

    /// The student record's Meetings tab writes these two; the workflow
    /// doesn't show them, so its saves carry them through untouched.
    @ObservationIgnored private var storedFocusText = ""
    @ObservationIgnored private var storedIsCompleted = false

    @ObservationIgnored private var isLoading = false
    @ObservationIgnored private var isWriting = false
    @ObservationIgnored private var hasUnsavedChanges = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(studentID: UUID) {
        self.studentID = studentID
    }

    // MARK: - Load & save

    func load(context: NSManagedObjectContext) {
        isLoading = true
        defer { isLoading = false }
        let data = MeetingPersistenceService.loadCurrent(studentID: studentID)
        storedFocusText = data.focusText
        storedIsCompleted = data.isCompleted
        reflection = data.reflectionText
        guideNotes = data.guideNotesText
        requestTexts = data.requestsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed() }
            .filter { !$0.isEmpty }
        requestLessonIDs = (data.requestLessonIDs ?? []).compactMap(UUID.init(uuidString:))
        nextMeetingDate = data.nextMeetingDate
        pendingFocus = (data.pendingFocusTexts ?? []).map { PendingFocusItem(text: $0) }
        resolvedFocusIDs = Set((data.resolvedFocusIDs ?? []).compactMap(UUID.init(uuidString:)))
        droppedFocusIDs = Set((data.droppedFocusIDs ?? []).compactMap(UUID.init(uuidString:)))
        workNotes = Dictionary(
            (data.workReviewDrafts ?? [:]).compactMap { key, value in UUID(uuidString: key).map { ($0, value) } },
            uniquingKeysWith: { first, _ in first }
        )
        reviewedWorkIDs = Set((data.reviewedWorkIDs ?? []).compactMap(UUID.init(uuidString:)))
        representWorkIDs = Set((data.representWorkIDs ?? []).compactMap(UUID.init(uuidString:)))
        readyWorkIDs = Set((data.readyWorkIDs ?? []).compactMap(UUID.init(uuidString:)))
        closeTokens = Dictionary(
            (data.closeTokens ?? [:]).compactMap { key, value in UUID(uuidString: key).map { ($0, value) } },
            uniquingKeysWith: { first, _ in first }
        )
        savedAt = data.isEmpty ? nil : Date()
        activeFocusItems = FocusItemService.fetchActive(studentID: studentID, context: context)
        lessonsWithNext = Self.lessonsWithNext(in: context)
    }

    /// Whether Ready for Next has a lesson to put On Deck after `lessonID`.
    func hasNextLesson(after lessonID: String) -> Bool {
        UUID(uuidString: lessonID).map(lessonsWithNext.contains) ?? false
    }

    /// Ready for Next plans what `PlanNextLessonService.findNextLesson` finds:
    /// the lesson after this one in its area and sequence. One lesson fetch.
    /// Lessons tied for last place count as having none, so the button never
    /// offers a plan Complete can't make.
    private static func lessonsWithNext(in context: NSManagedObjectContext) -> Set<UUID> {
        var sequences: [String: [CDLesson]] = [:]
        for lesson in context.safeFetch(CDFetchRequest(CDLesson.self)) {
            let area = lesson.area.trimmed().lowercased()
            let sequence = lesson.sequence.trimmed().lowercased()
            guard !area.isEmpty, !sequence.isEmpty else { continue }
            sequences[area + "\u{1F}" + sequence, default: []].append(lesson)
        }
        var result: Set<UUID> = []
        for lessons in sequences.values {
            guard let last = lessons.map(\.orderInSequence).max() else { continue }
            for lesson in lessons where lesson.orderInSequence < last {
                if let id = lesson.id { result.insert(id) }
            }
        }
        return result
    }

    var data: MeetingPersistenceService.CurrentMeetingData {
        MeetingPersistenceService.CurrentMeetingData(
            isCompleted: storedIsCompleted,
            reflectionText: reflection,
            focusText: storedFocusText,
            requestsText: allRequestTexts.joined(separator: "\n"),
            guideNotesText: guideNotes,
            nextMeetingDate: nextMeetingDate,
            pendingFocusTexts: pendingFocus.map(\.text),
            resolvedFocusIDs: resolvedFocusIDs.map(\.uuidString),
            droppedFocusIDs: droppedFocusIDs.map(\.uuidString),
            workReviewDrafts: Dictionary(uniqueKeysWithValues: workNotes.map { ($0.key.uuidString, $0.value) }),
            reviewedWorkIDs: reviewedWorkIDs.map(\.uuidString),
            requestLessonIDs: requestLessonIDs.map(\.uuidString),
            representWorkIDs: representWorkIDs.map(\.uuidString),
            readyWorkIDs: readyWorkIDs.map(\.uuidString),
            closeTokens: Dictionary(uniqueKeysWithValues: closeTokens.map { ($0.key.uuidString, $0.value) })
        )
    }

    var isEmpty: Bool { data.isEmpty }

    /// The free-text requests, with anything still typed in the field as one more.
    private var allRequestTexts: [String] {
        let pending = requestQuery.trimmed()
        guard !pending.isEmpty, !requestTexts.contains(pending) else { return requestTexts }
        return requestTexts + [pending]
    }

    private func changed() {
        guard !isLoading else { return }
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes the draft now (leaving the child, the app going to the background),
    /// when something changed since it was loaded or last written.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        // The tab may have written its fields since this draft was loaded.
        let stored = MeetingPersistenceService.loadCurrent(studentID: studentID)
        storedFocusText = stored.focusText
        storedIsCompleted = stored.isCompleted
        let snapshot = data
        isWriting = true
        MeetingPersistenceService.saveCurrent(studentID: studentID, data: snapshot)
        isWriting = false
        savedAt = snapshot.isEmpty && snapshot.nextMeetingDate == nil ? nil : Date()
    }

    /// The stored drafts changed. When this child's was cleared or filed
    /// somewhere else (the student record's Meetings tab, or her meeting open
    /// in a second window) while this one still holds it, drop what this one
    /// holds without writing: its next save would otherwise put back Re-present
    /// and Ready decisions, and their receipts, for work already taken back or
    /// planned (bug hunt 2026-10-09 review).
    func storedDraftsChanged() {
        guard !isLoading, !isWriting, savedAt != nil,
              !MeetingPersistenceService.hasDraft(studentID: studentID) else { return }
        clear()
    }

    /// Clear Meeting: Re-present and Ready for Next closed their work at once
    /// but plan their lessons only on Complete, so that work goes back as it
    /// was before the meeting rather than staying closed with nothing
    /// planned (`MeetingLessonDecisions.takeBack`). Then the form is emptied.
    func discard(context: NSManagedObjectContext) {
        MeetingLessonDecisions.takeBack(data, context: context)
        clear()
    }

    /// Empties the form and removes the stored draft.
    func clear() {
        saveTask?.cancel()
        saveTask = nil
        isLoading = true
        reflection = ""
        guideNotes = ""
        requestLessonIDs = []
        requestTexts = []
        requestQuery = ""
        nextMeetingDate = nil
        pendingFocus = []
        resolvedFocusIDs = []
        droppedFocusIDs = []
        workNotes = [:]
        reviewedWorkIDs = []
        representWorkIDs = []
        readyWorkIDs = []
        closeTokens = [:]
        storedFocusText = ""
        storedIsCompleted = false
        isLoading = false
        hasUnsavedChanges = false
        savedAt = nil
        MeetingPersistenceService.clearCurrent(studentID: studentID)
    }

    // MARK: - Work decisions

    /// Applies a status from a decision card at once (through `WorkLogService`,
    /// the only status writer) and counts the item as reviewed. A choice made
    /// earlier on the card is taken back first, so its close doesn't leave
    /// skipped check-ins, completed todos or a completion record behind; work
    /// changed since then takes the new status on top. One save; returns
    /// false, with nothing changed or recorded, when it didn't save.
    @discardableResult
    func decide(_ work: CDWorkModel, status: WorkStatus, context: NSManagedObjectContext) -> Bool {
        let transaction = ContextMutationTransaction(context: context)
        _ = takeBackEarlierChoice(on: work, context: context)
        if work.isResting { MeetingReviewService.clearWorkResting(work) }
        var receipt: WorkLogService.Receipt?
        if work.status != status {
            do {
                receipt = try WorkLogService.log(
                    [.init(work: work, status: status)], context: context, saveImmediately: false
                )
            } catch {
                transaction.rollback()
                ToastService.shared.showError(Self.decisionFailure)
                return false
            }
        }
        work.lastTouchedAt = Date()
        let token = receipt.flatMap { MeetingCloseToken($0.token, leaving: work, in: context) }
        guard context.safeSave() else {
            transaction.rollback()
            ToastService.shared.showError(Self.decisionFailure)
            return false
        }
        transaction.commit()
        guard let id = work.id else { return true }
        forgetLessonDecision(id)
        closeTokens[id] = token.map { [$0] }
        reviewedWorkIDs.insert(id)
        return true
    }

    /// The work didn't take: it closes as Incomplete now, and Complete plans
    /// its lesson again as a second pass.
    func represent(_ work: CDWorkModel, context: NSManagedObjectContext) {
        guard decide(work, status: .incomplete, context: context), let id = work.id else { return }
        representWorkIDs.insert(id)
    }

    /// She's ready to move on: the work closes with no mastery mark (ready
    /// isn't mastered), and Complete confirms her on the lesson and puts the
    /// next one in the sequence On Deck.
    func readyForNext(_ work: CDWorkModel, context: NSManagedObjectContext) {
        guard decide(work, status: .done, context: context), let id = work.id else { return }
        readyWorkIDs.insert(id)
    }

    /// Another outcome replaces a Re-present or Ready for Next chosen earlier.
    private func forgetLessonDecision(_ id: UUID) {
        representWorkIDs.remove(id)
        readyWorkIDs.remove(id)
    }

    /// Takes back, in memory, the statuses the card's earlier choices set in
    /// this meeting, newest first (the caller saves).
    private func takeBackEarlierChoice(
        on work: CDWorkModel, context: NSManagedObjectContext
    ) -> MeetingCloseToken.TakeBack {
        guard let id = work.id else { return .nothing }
        return MeetingCloseToken.takeBack(closeTokens[id] ?? [], of: work, in: context)
    }

    /// Resting work is open: a status the card set in this meeting is taken
    /// back, and Re-present or Ready work with no receipt to take back goes
    /// back to Working, as Clear does (bug hunt 2026-10-09, #10). Work changed
    /// since keeps its status and rests.
    func rest(_ work: CDWorkModel, until date: Date, context: NSManagedObjectContext) {
        let transaction = ContextMutationTransaction(context: context)
        let wasLessonDecision = work.id.map { representWorkIDs.contains($0) || readyWorkIDs.contains($0) } ?? false
        let takeBack = takeBackEarlierChoice(on: work, context: context)
        if wasLessonDecision, takeBack == .nothing || takeBack == .unreadable, work.status.isClosed {
            do {
                try WorkLogService.log([.init(work: work, status: .active)], context: context, saveImmediately: false)
            } catch {
                transaction.rollback()
                ToastService.shared.showError(Self.decisionFailure)
                return
            }
        }
        MeetingReviewService.setWorkResting(work, until: date)
        work.lastTouchedAt = Date()
        guard context.safeSave() else {
            transaction.rollback()
            ToastService.shared.showError(Self.decisionFailure)
            return
        }
        transaction.commit()
        guard let id = work.id else { return }
        forgetLessonDecision(id)
        closeTokens[id] = nil
        reviewedWorkIDs.insert(id)
    }

    /// A decision card that didn't save says so; `safeSave` has logged why.
    private static let decisionFailure = "Couldn't save that decision about the work. Try again."

    // MARK: - Complete

    /// Files the meeting: history, work reviews, focus changes, requested
    /// lessons to the inbox, today's booking cleared and the next one booked.
    /// Returns false (form kept) when the save fails.
    func complete(
        context: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator,
        lessonName: (UUID) -> String?
    ) -> Bool {
        let resolvedItems = activeFocusItems.filter { resolvedFocusIDs.contains($0.id ?? UUID()) }
        let carryForward = activeFocusItems.filter {
            guard let id = $0.id else { return false }
            return !resolvedFocusIDs.contains(id) && !droppedFocusIDs.contains(id)
        }
        var completed = data
        completed.isCompleted = true
        // The checklist, then any focus typed on the student record's Meetings tab.
        let typedFocus = MeetingPersistenceService.loadCurrent(studentID: studentID).focusText.trimmed()
        completed.focusText = [
            FocusItemService.snapshotText(
                activeItems: carryForward,
                resolvedItems: resolvedItems,
                newTexts: pendingFocus.map(\.text)
            ),
            typedFocus
        ].filter { !$0.isEmpty }.joined(separator: "\n")
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
        persistFocus(meetingID: meetingID, context: context)
        let planned: Set<UUID>
        do {
            planned = try MeetingLessonDecisions.file(data, studentID: studentID, context: context)
        } catch {
            transaction.rollback()
            return false
        }
        for lessonID in requestLessonIDs where !planned.contains(lessonID) {
            _ = PresentationFactory.makeDraft(lessonID: lessonID, studentIDs: [studentID], context: context)
        }
        _ = MeetingScheduler.completeBooking(studentID: studentID, heldOn: Date(), context: context)

        // A failure shows the "Couldn't Save" alert and keeps the form open
        // so the meeting record isn't silently lost.
        guard saveCoordinator.save(context, reason: "Save meeting") else {
            transaction.rollback()
            return false
        }
        transaction.commit()

        if let next = nextMeetingDate {
            MeetingScheduler.scheduleMeeting(studentID: studentID, date: next, context: context)
        }
        clear()
        activeFocusItems = FocusItemService.fetchActive(studentID: studentID, context: context)
        return true
    }

    private func persistFocus(meetingID: UUID, context: NSManagedObjectContext) {
        for item in activeFocusItems {
            guard let itemID = item.id else { continue }
            if resolvedFocusIDs.contains(itemID) {
                FocusItemService.resolve(item, inMeetingID: meetingID)
            } else if droppedFocusIDs.contains(itemID) {
                FocusItemService.drop(item, inMeetingID: meetingID)
            }
        }
        let existingCount = activeFocusItems.count
        for (index, pending) in pendingFocus.enumerated() {
            let trimmed = pending.text.trimmed()
            guard !trimmed.isEmpty else { continue }
            FocusItemService.create(
                studentID: studentID, text: trimmed, meetingID: meetingID,
                sortOrder: existingCount + index, context: context
            )
        }
    }
}
