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
        representWorkIDs = Set((data.representWorkIDs ?? []).compactMap(UUID.init(uuidString:)))
        readyWorkIDs = Set((data.readyWorkIDs ?? []).compactMap(UUID.init(uuidString:)))
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
            requestLessonIDs: requestLessonIDs.map(\.uuidString),
            representWorkIDs: representWorkIDs.map(\.uuidString),
            readyWorkIDs: readyWorkIDs.map(\.uuidString)
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

    /// Clear Meeting: Re-present and Ready for Next closed their work at once
    /// but plan their lessons only on Complete, so that work goes back to
    /// Working rather than staying closed with nothing planned. Then the
    /// form is emptied.
    func discard(context: NSManagedObjectContext) {
        let pending = representWorkIDs.union(readyWorkIDs)
        if !pending.isEmpty {
            let request = CDFetchRequest(CDWorkModel.self)
            request.predicate = NSPredicate(format: "id IN %@", Array(pending))
            let works = context.safeFetch(request).filter { $0.status.isClosed }
            do {
                if !works.isEmpty {
                    try WorkLogService.log(works.map { .init(work: $0, status: .active) }, context: context)
                }
            } catch {
                ToastService.shared.showError("Couldn't put the work back to Working. Open it to change it by hand.")
            }
        }
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
        storedFocusText = ""
        storedIsCompleted = false
        isLoading = false
        hasUnsavedChanges = false
        savedAt = nil
        MeetingPersistenceService.clearCurrent(studentID: studentID)
    }

    // MARK: - Work decisions

    /// Applies a status from a decision card at once (through `WorkLogService`,
    /// the only status writer) and counts the item as reviewed. Returns false
    /// when it didn't save.
    @discardableResult
    func decide(_ work: CDWorkModel, status: WorkStatus, context: NSManagedObjectContext) -> Bool {
        forgetLessonDecision(work)
        if work.isResting { MeetingReviewService.clearWorkResting(work) }
        if work.status != status {
            do {
                try WorkLogService.log([.init(work: work, status: status)], context: context, saveImmediately: false)
            } catch {
                ToastService.shared.showError(Self.decisionFailure)
                return false
            }
        }
        markReviewed(work)
        guard context.safeSave() else {
            ToastService.shared.showError(Self.decisionFailure)
            return false
        }
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
    private func forgetLessonDecision(_ work: CDWorkModel) {
        guard let id = work.id else { return }
        representWorkIDs.remove(id)
        readyWorkIDs.remove(id)
    }

    func rest(_ work: CDWorkModel, until date: Date, context: NSManagedObjectContext) {
        forgetLessonDecision(work)
        MeetingReviewService.setWorkResting(work, until: date)
        markReviewed(work)
        if !context.safeSave() { ToastService.shared.showError(Self.decisionFailure) }
    }

    /// A decision card that didn't save says so; `safeSave` has logged why.
    private static let decisionFailure = "Couldn't save that decision about the work. Try again."

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
        let planned: Set<UUID>
        do {
            planned = try persistRepresentations(context: context)
                .union(planNextLessons(context: context))
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

    /// Plans each re-presented work's lesson again, flagging the presentation
    /// that didn't take the way a presentation review's Re-present does.
    /// Returns the lessons it planned, so a request for one isn't filed twice.
    private func persistRepresentations(context: NSManagedObjectContext) throws -> Set<UUID> {
        var lessonIDs: Set<UUID> = []
        for workID in representWorkIDs {
            guard let (work, lesson) = workAndLesson(workID, context: context),
                  let lessonID = lesson.id else { continue }
            if let presentation = presentation(of: work, context: context) {
                presentation.needsAnotherPresentation = true
                presentation.modifiedAt = Date()
            }
            resolveFollowUp(of: work, as: .supportOrRepresent, context: context)
            try CaptureFollowUpPersistence.createRepresentationIfNeeded(
                studentID: studentID, lesson: lesson, context: context
            )
            lessonIDs.insert(lessonID)
        }
        return lessonIDs
    }

    /// Confirms her on each ready work's lesson (not a mastery mark) and puts
    /// the next lesson in its sequence On Deck, unless she already has it planned.
    /// Returns those next lessons, so a request for one isn't filed twice.
    private func planNextLessons(context: NSManagedObjectContext) -> Set<UUID> {
        guard !readyWorkIDs.isEmpty else { return [] }
        var lessonIDs: Set<UUID> = []
        let allLessons = context.safeFetch(CDFetchRequest(CDLesson.self))
        for workID in readyWorkIDs {
            guard let (work, lesson) = workAndLesson(workID, context: context) else { continue }
            presentation(of: work, context: context)?.confirmStudent(studentID)
            resolveFollowUp(of: work, as: .readyForNextPresentation, context: context)
            guard let next = PlanNextLessonService.findNextLesson(after: lesson, in: allLessons),
                  let nextID = next.id else { continue }
            lessonIDs.insert(nextID)
            let request = CDFetchRequest(CDLessonAssignment.self)
            request.predicate = NSPredicate(format: "lessonID == %@", nextID.uuidString)
            let existing = context.safeFetch(request).filter { !$0.isPresented && !$0.isDeleted }
            guard !existing.contains(where: { $0.resolvedStudentIDs.contains(studentID) }) else { continue }
            PlanNextLessonService.planLesson(
                next, forStudents: [studentID], allStudents: [], allLessons: allLessons,
                existingLessonAssignments: existing, context: context
            )
        }
        return lessonIDs
    }

    private func workAndLesson(_ workID: UUID, context: NSManagedObjectContext) -> (CDWorkModel, CDLesson)? {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id == %@", workID as CVarArg)
        request.fetchLimit = 1
        guard let work = context.safeFetch(request).first,
              let lessonID = UUID(uuidString: work.lessonID) else { return nil }
        let lessonRequest = CDFetchRequest(CDLesson.self)
        lessonRequest.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
        lessonRequest.fetchLimit = 1
        guard let lesson = context.safeFetch(lessonRequest).first else { return nil }
        return (work, lesson)
    }

    /// The presentation the work came from, if it came from one.
    private func presentation(of work: CDWorkModel, context: NSManagedObjectContext) -> CDLessonAssignment? {
        guard let id = work.presentationID.flatMap(UUID.init(uuidString:)) else { return nil }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetch(request).first
    }

    /// Closes her follow-up on the work's presentation the way the
    /// presentation review would for the same decision.
    private func resolveFollowUp(
        of work: CDWorkModel, as resolution: PresentationFollowUpResolution, context: NSManagedObjectContext
    ) {
        guard let id = work.presentationID.flatMap(UUID.init(uuidString:)) else { return }
        let now = Date()
        for row in PresentationFollowUpService.rows(for: id, in: context) where row.studentID == studentID.uuidString {
            PresentationFollowUpService.resolve(resolution, row: row, at: now)
        }
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
