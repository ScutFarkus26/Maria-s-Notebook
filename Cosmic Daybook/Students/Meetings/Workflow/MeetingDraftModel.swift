import Foundation
import CoreData

/// A pending focus item that hasn't been persisted yet (created during this meeting session).
struct PendingFocusItem: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

/// One child's meeting in progress: the form, the focus checklist, the work
/// decisions, the lesson requests and what the guide owes her (For Me to Do). The header, decision cards, form and
/// footer all read this one object, so a layout switch (a window resized
/// across the wide/narrow line) rebuilds views without losing anything.
///
/// Drafts are saved on a short debounce after the last change and flushed
/// when the meeting is left, then removed when it is completed or cleared. A
/// work card's decision is written at once (`+Decisions`).
///
/// The child's meeting can be open in two windows (Mac, iPad), each with its
/// own model on the one stored draft. A model writes only what it changed,
/// field by field, and item by item for focus ticks, each work's note,
/// each work's decision and receipt, and each For Me to Do line and tick, taking the rest from the stored draft;
/// and it takes up the stored draft's changes as they come (bug hunt
/// 2026-10-10, #11 and its review).
@Observable @MainActor
final class MeetingDraftModel {
    typealias Draft = MeetingPersistenceService.CurrentMeetingData

    let studentID: UUID

    var reflection = "" { didSet { changed(.reflection) } }
    var guideNotes = "" { didSet { changed(.guideNotes) } }
    /// Catalog lessons asked for; they go to the inbox on Complete.
    var requestLessonIDs: [UUID] = [] { didSet { changed(.requestLessonIDs) } }
    /// Requests that matched no lesson, kept as the guide typed them.
    var requestTexts: [String] = [] { didSet { changed(.requests) } }
    /// What is typed in the request field and not yet added. Saved with the
    /// draft as a free-text request, and filed as one on Complete, so moving
    /// on doesn't drop it.
    var requestQuery = "" { didSet { changed(.requests) } }
    var nextMeetingDate: Date? { didSet { changed(.nextMeetingDate) } }

    var pendingFocus: [PendingFocusItem] = [] { didSet { changed(.pendingFocus) } }
    var resolvedFocusIDs: Set<UUID> = [] {
        didSet { changed(\.focusIDs, oldValue.symmetricDifference(resolvedFocusIDs)) }
    }
    var droppedFocusIDs: Set<UUID> = [] {
        didSet { changed(\.focusIDs, oldValue.symmetricDifference(droppedFocusIDs)) }
    }

    var workNotes: [UUID: String] = [:] { didSet { changed(\.noteWorkIDs, Self.changedKeys(oldValue, workNotes)) } }
    var reviewedWorkIDs: Set<UUID> = [] {
        didSet { changed(\.decisionWorkIDs, oldValue.symmetricDifference(reviewedWorkIDs)) }
    }
    /// Work decided as Re-present: closed as Incomplete now, its lesson
    /// planned again as a second pass on Complete.
    var representWorkIDs: Set<UUID> = [] {
        didSet { changed(\.decisionWorkIDs, oldValue.symmetricDifference(representWorkIDs)) }
    }
    /// Work switched to Ready for Next: its next lesson goes On Deck on
    /// Complete. A switch beside the card's choice, not a choice itself: it
    /// leaves the work's status alone and goes with any choice but Re-present.
    var readyWorkIDs: Set<UUID> = [] {
        didSet { changed(\.decisionWorkIDs, oldValue.symmetricDifference(readyWorkIDs)) }
    }
    /// The `WorkLogService` receipt of the status each card's choice set,
    /// kept with the draft so Clear, Rest or another outcome can take the
    /// close back after a relaunch, not just log Working on top of it
    /// (bug hunt 2026-10-09, #9 and #10). A list, oldest first, read newest
    /// first; a card's next choice takes the earlier one back, so it rarely
    /// holds more than one.
    var closeTokens: [UUID: [MeetingCloseToken]] = [:] {
        didSet { changed(\.decisionWorkIDs, Self.changedKeys(oldValue, closeTokens)) }
    }

    /// For Me to Do: lines typed for her, filed as to-dos naming her on Complete.
    var newTodos: [MeetingNewTodo] = [] {
        didSet { changed(\.newTodoIDs, Self.changedKeys(Self.byID(oldValue), Self.byID(newTodos))) }
    }
    /// For Me to Do: her open to-dos ticked here, completed on Complete.
    var doneTodoIDs: Set<UUID> = [] {
        didSet { changed(\.doneTodoIDs, oldValue.symmetricDifference(doneTodoIDs)) }
    }

    /// Focus items carried from earlier meetings.
    private(set) var activeFocusItems: [CDStudentFocusItem] = []
    /// When the draft last reached disk; nil until something is written.
    private(set) var savedAt: Date?
    /// The next lesson's name for each lesson with one in its sequence,
    /// worked out once when the draft loads, so a card's Ready for Next reads
    /// a table rather than the catalog (bug hunt 2026-10-09, #13).
    private(set) var nextLessonNames: [UUID: String] = [:]

    /// The student record's Meetings tab writes these two; the workflow
    /// doesn't show them, so its saves carry them through untouched.
    @ObservationIgnored private var storedFocusText = ""
    @ObservationIgnored private var storedIsCompleted = false

    @ObservationIgnored private var isLoading = false
    /// Set while this model reads or writes the stored draft, so the change
    /// notices its own write posts aren't taken for another window's.
    @ObservationIgnored private var isWriting = false
    @ObservationIgnored private var hasUnsavedChanges = false
    /// What this model changed since it last wrote; on everything else the
    /// stored draft has the newer word.
    @ObservationIgnored private var changes = Changes()
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(studentID: UUID) {
        self.studentID = studentID
    }

    // MARK: - Load & save

    func load(context: NSManagedObjectContext) {
        changes = Changes()
        takeUp(readStored())
        savedAt = data.isEmpty ? nil : Date()
        activeFocusItems = FocusItemService.fetchActive(studentID: studentID, context: context)
        nextLessonNames = Self.nextLessonNames(in: context)
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
            closeTokens: Dictionary(uniqueKeysWithValues: closeTokens.map { ($0.key.uuidString, $0.value) }),
            newTodos: newTodos,
            doneTodoIDs: doneTodoIDs.map(\.uuidString).sorted()
        )
    }

    var isEmpty: Bool { data.isEmpty }

    /// The free-text requests, with anything still typed in the field as one more.
    var allRequestTexts: [String] {
        let pending = requestQuery.trimmed()
        guard !pending.isEmpty, !requestTexts.contains(pending) else { return requestTexts }
        return requestTexts + [pending]
    }

    /// A field changed here.
    private func changed(_ field: Field) {
        guard !isLoading else { return }
        changes.fields.insert(field)
        scheduleSave()
    }

    /// Items of a keyed field changed here: focus ticks, notes, decisions.
    private func changed(_ items: WritableKeyPath<Changes, Set<UUID>>, _ ids: Set<UUID>) {
        guard !isLoading, !ids.isEmpty else { return }
        changes[keyPath: items].formUnion(ids)
        scheduleSave()
    }

    private func scheduleSave() {
        hasUnsavedChanges = true
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Writes the draft now (leaving the child, the app going to the background),
    /// when something changed since it was loaded or last written. What the
    /// tab or a second window stored since, this one takes up first, wherever
    /// it hasn't changed the same thing itself.
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard hasUnsavedChanges else { return }
        hasUnsavedChanges = false
        let wasWriting = isWriting
        isWriting = true
        defer { isWriting = wasWriting }
        takeUp(MeetingPersistenceService.loadCurrent(studentID: studentID))
        changes = Changes()
        let snapshot = data
        MeetingPersistenceService.saveCurrent(studentID: studentID, data: snapshot)
        savedAt = snapshot.isEmpty && snapshot.nextMeetingDate == nil ? nil : Date()
    }

    /// This child's stored draft changed somewhere else: the student record's
    /// Meetings tab, or her meeting open in a second window.
    ///
    /// Cleared or filed while this one still holds it: drop what this one
    /// holds without writing, as its next save would otherwise put back
    /// Re-present and Ready decisions, and their receipts, for work already
    /// taken back or planned (bug hunt 2026-10-09 review). Written: take it
    /// up wherever this one has nothing of its own waiting to be saved (bug
    /// hunt 2026-10-10, #11).
    func storedDraftsChanged() {
        guard !isLoading, !isWriting else { return }
        if savedAt != nil, !MeetingPersistenceService.hasDraft(studentID: studentID) {
            clear()
            return
        }
        takeUpStored()
        if !hasUnsavedChanges {
            savedAt = data.isEmpty ? nil : (savedAt ?? Date())
        }
    }

    /// Clear Meeting: Re-present closed its work at once but plans its lesson
    /// only on Complete, so that work goes back as it was before the meeting
    /// rather than staying closed with nothing planned
    /// (`MeetingLessonDecisions.takeBack`). Ready for Next changed nothing
    /// yet and just goes. Then the form is emptied.
    /// When the work couldn't be put back, the form and the stored draft stay,
    /// receipts and all, for another try (bug hunt 2026-10-10, #12).
    @discardableResult
    func discard(context: NSManagedObjectContext) -> Bool {
        takeUpStored()
        guard MeetingLessonDecisions.takeBack(data, context: context) else { return false }
        clear()
        return true
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
        newTodos = []
        doneTodoIDs = []
        storedFocusText = ""
        storedIsCompleted = false
        isLoading = false
        hasUnsavedChanges = false
        changes = Changes()
        savedAt = nil
        MeetingPersistenceService.clearCurrent(studentID: studentID)
    }

    /// The carried focus items, fetched again (after Complete has filed them).
    func refreshFocusItems(context: NSManagedObjectContext) {
        activeFocusItems = FocusItemService.fetchActive(studentID: studentID, context: context)
    }

    // MARK: - Taking up the stored draft

    /// Before a card's decision, Clear or Complete: the stored draft's word
    /// on everything this model hasn't changed, so a card takes back the
    /// newest receipt and filing sees both windows' decisions.
    func takeUpStored() {
        takeUp(readStored())
    }

    /// The stored draft, wherever this model has nothing of its own waiting
    /// to be saved: field by field, and item by item for focus ticks, each
    /// work's note and each work's decision and receipt. A stale window can
    /// then neither erase a Re-present made elsewhere nor bring back one
    /// switched off there, nor write back text another window changed (bug
    /// hunt 2026-10-10, #11 and its review). A field already holding the
    /// value is left alone, so only what moved redraws. Writes nothing.
    private func takeUp(_ stored: Draft) {
        let wasLoading = isLoading
        isLoading = true
        defer { isLoading = wasLoading }
        let mine = changes
        storedFocusText = stored.focusText
        storedIsCompleted = stored.isCompleted
        if !mine.fields.contains(.reflection) { update(\.reflection, to: stored.reflectionText) }
        if !mine.fields.contains(.guideNotes) { update(\.guideNotes, to: stored.guideNotesText) }
        if !mine.fields.contains(.requests) { update(\.requestTexts, to: requestTexts(in: stored)) }
        if !mine.fields.contains(.requestLessonIDs) {
            update(\.requestLessonIDs, to: (stored.requestLessonIDs ?? []).compactMap(UUID.init(uuidString:)))
        }
        if !mine.fields.contains(.nextMeetingDate) { update(\.nextMeetingDate, to: stored.nextMeetingDate) }
        if !mine.fields.contains(.pendingFocus), pendingFocus.map(\.text) != (stored.pendingFocusTexts ?? []) {
            pendingFocus = (stored.pendingFocusTexts ?? []).map { PendingFocusItem(text: $0) }
        }
        let focus = mine.focusIDs
        update(\.resolvedFocusIDs, to: Self.merged(resolvedFocusIDs, Self.ids(stored.resolvedFocusIDs), keeping: focus))
        update(\.droppedFocusIDs, to: Self.merged(droppedFocusIDs, Self.ids(stored.droppedFocusIDs), keeping: focus))
        update(\.workNotes, to: Self.merged(workNotes, Self.keyed(stored.workReviewDrafts), keeping: mine.noteWorkIDs))
        let work = mine.decisionWorkIDs
        update(\.reviewedWorkIDs, to: Self.merged(reviewedWorkIDs, Self.ids(stored.reviewedWorkIDs), keeping: work))
        update(\.representWorkIDs, to: Self.merged(representWorkIDs, Self.ids(stored.representWorkIDs), keeping: work))
        update(\.readyWorkIDs, to: Self.merged(readyWorkIDs, Self.ids(stored.readyWorkIDs), keeping: work))
        update(\.closeTokens, to: Self.merged(closeTokens, Self.keyed(stored.closeTokens), keeping: work))
        update(\.newTodos, to: Self.merged(newTodos, stored.newTodos ?? [], keeping: mine.newTodoIDs))
        update(\.doneTodoIDs, to: Self.merged(doneTodoIDs, Self.ids(stored.doneTodoIDs), keeping: mine.doneTodoIDs))
    }

    /// The stored free-text requests. Text still in the request field reaches
    /// the store as a request; it stays in the field rather than showing twice.
    private func requestTexts(in stored: Draft) -> [String] {
        let typed = requestQuery.trimmed()
        return stored.requestsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed() }
            .filter { !$0.isEmpty && $0 != typed }
    }

    /// The stored draft, read with this model's change handler muted (a
    /// draft still in the old keys is moved into its blob on first read).
    func readStored() -> Draft {
        let wasWriting = isWriting
        isWriting = true
        defer { isWriting = wasWriting }
        return MeetingPersistenceService.loadCurrent(studentID: studentID)
    }

    private func update<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<MeetingDraftModel, Value>, to value: Value
    ) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }
}
