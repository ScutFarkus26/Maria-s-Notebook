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

    /// Focus items carried from earlier meetings.
    private(set) var activeFocusItems: [CDStudentFocusItem] = []
    /// When the draft last reached disk; nil until something is written.
    private(set) var savedAt: Date?

    /// The student record's Meetings tab writes these two; the workflow
    /// doesn't show them, so its saves carry them through untouched.
    @ObservationIgnored private var storedFocusText = ""
    @ObservationIgnored private var storedIsCompleted = false

    @ObservationIgnored private var isLoading = false
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
        savedAt = data.isEmpty ? nil : Date()
        activeFocusItems = FocusItemService.fetchActive(studentID: studentID, context: context)
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
            requestLessonIDs: requestLessonIDs.map(\.uuidString)
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
        MeetingPersistenceService.saveCurrent(studentID: studentID, data: snapshot)
        savedAt = snapshot.isEmpty && snapshot.nextMeetingDate == nil ? nil : Date()
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
        storedFocusText = ""
        storedIsCompleted = false
        isLoading = false
        hasUnsavedChanges = false
        savedAt = nil
        MeetingPersistenceService.clearCurrent(studentID: studentID)
    }

    // MARK: - Work decisions

    /// Applies a status from a decision card at once (through `WorkLogService`,
    /// the only status writer) and counts the item as reviewed.
    func decide(_ work: CDWorkModel, status: WorkStatus, context: NSManagedObjectContext) {
        if work.isResting { MeetingReviewService.clearWorkResting(work) }
        if work.status != status {
            do {
                try WorkLogService.log([.init(work: work, status: status)], context: context, saveImmediately: false)
            } catch { return }
        }
        markReviewed(work)
        context.safeSave()
    }

    func rest(_ work: CDWorkModel, until date: Date, context: NSManagedObjectContext) {
        MeetingReviewService.setWorkResting(work, until: date)
        markReviewed(work)
        context.safeSave()
    }

    func markReviewed(_ work: CDWorkModel) {
        guard let id = work.id else { return }
        reviewedWorkIDs.insert(id)
        work.lastTouchedAt = Date()
    }

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
        for lessonID in requestLessonIDs {
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
