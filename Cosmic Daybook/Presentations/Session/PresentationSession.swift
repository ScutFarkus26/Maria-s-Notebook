// PresentationSession.swift
// One presentation, from "who was there?" to "what's next for each child".
//
// The presentation sheet has two beats on one surface: Record (who received it,
// on which day) and How It Went (one note, one decision per child). This model
// holds both, so nothing is split between a sheet, its parent and a third
// editor. Recording saves at once and can be undone for the whole session;
// the notes and decisions wait for Done (or Later, which saves the notes and
// keeps the decisions as a draft).

import CoreData
import Foundation

@Observable
final class PresentationSession {
    enum Phase: Equatable, Sendable {
        case who
        case howItWent
    }

    let presentationID: UUID

    // MARK: - Beat 1: who was there

    private(set) var phase: Phase = .who
    /// The day being recorded. Today unless the guide picks an earlier day.
    var presentedDay: Date = AppCalendar.startOfDay(Date())
    /// The children ticked as having received the lesson.
    private(set) var presentIDs: Set<UUID> = []
    /// Children the day's attendance marks absent.
    private(set) var absentIDs: Set<UUID> = []
    /// Ticks the guide changed by hand; a new day's attendance leaves them alone.
    private var touchedIDs: Set<UUID> = []

    /// The receipt for undoing the recording; held for the whole session.
    var undoToken: ImmediatePresentationRecordingService.UndoToken?
    /// Children taken off at Record because they weren't there.
    var keptOnPlanNames: [String] = []

    // MARK: - Beat 2: how it went

    var groupNote = ""
    var childNotes: [UUID: String] = [:]
    /// The Everyone row's choice; each child inherits it unless overridden.
    private(set) var everyone = PresentationChoice(.continueObserving)
    private(set) var overrides: [UUID: PresentationChoice] = [:]
    /// The check-in day shown on the sheet. Set it through `pickCheckIn`, so
    /// a day the guide picks is told from the one the sheet put there.
    private(set) var checkIn: PresentationCheckIn = .nextWorkCycle
    /// Each child's day from `PracticeCheckInTiming`, as chat files it, when
    /// the sheet starts from it (nothing is decided on the record yet). The
    /// sheet shows the earliest; each child gets her own unless the guide
    /// picks a day.
    private(set) var timedCheckIns: [UUID: Date] = [:]
    /// Whether the guide chose the check-in on the sheet.
    private(set) var checkInPicked = false
    /// What the follow-up work is, as its title; blank gives "Follow up: <lesson>".
    var followUpDetail = ""
    /// Where the next lesson goes for the newly ready children. Nil until the
    /// guide chooses: the sheet then shows, and Done does, what would happen
    /// anyway (the year plan's day if it has one, otherwise the Inbox).
    var nextLessonPlace: PresentationNextLessonPlace?
    /// What each child already has on record, read when the beat opens.
    private(set) var applied: [UUID: PresentationChoice] = [:]
    private(set) var loadedCheckIn: PresentationCheckIn = .nextWorkCycle
    /// Set once Done or Later has handled the session, so closing the sheet
    /// afterwards does nothing more.
    private(set) var isFinished = false
    /// Set when How It Went first opens, so going back to Edit Details and
    /// on again keeps the decisions made, rather than reading them afresh.
    private(set) var hasOpenedHowItWent = false

    init(presentationID: UUID) {
        self.presentationID = presentationID
    }

    // MARK: - Roster

    /// Sets the ticks from the day's attendance: everyone on the plan is ticked
    /// except a child marked absent, unless the guide has already changed hers.
    func syncRoster(planned: Set<UUID>, absent: Set<UUID>) {
        absentIDs = absent.intersection(planned)
        touchedIDs.formIntersection(planned)
        var present = presentIDs.intersection(touchedIDs)
        for id in planned where !touchedIDs.contains(id) && !absentIDs.contains(id) {
            present.insert(id)
        }
        presentIDs = present
    }

    func togglePresent(_ id: UUID) {
        touchedIDs.insert(id)
        if presentIDs.contains(id) {
            presentIDs.remove(id)
        } else {
            presentIDs.insert(id)
        }
    }

    // MARK: - Phases

    func showHowItWent() {
        phase = .howItWent
        hasOpenedHowItWent = true
    }

    /// Undo took the recording back, so a new one reads its decisions afresh
    /// and closing the sheet keeps no draft for it.
    func forgetHowItWent() {
        hasOpenedHowItWent = false
        everyone = PresentationChoice(.continueObserving)
        overrides = [:]
        followUpDetail = ""
        nextLessonPlace = nil
        checkInPicked = false
        timedCheckIns = [:]
    }

    /// A check-in day the guide chose on the sheet: it wins over the timed one.
    func pickCheckIn(_ choice: PresentationCheckIn) {
        checkIn = choice
        checkInPicked = true
    }

    /// The days Done gives the work-giving children: each one's timed day,
    /// unless the guide picked a day (then `checkIn` is everyone's).
    var checkInDaysForDone: [UUID: Date] {
        checkInPicked ? [:] : timedCheckIns
    }

    func showWho() {
        phase = .who
    }

    func markFinished() {
        isFinished = true
    }

    // MARK: - Decisions

    func choice(for studentID: UUID) -> PresentationChoice {
        overrides[studentID] ?? everyone
    }

    func decision(for studentID: UUID) -> CaptureFollowUp {
        choice(for: studentID).decision
    }

    func isOverridden(_ studentID: UUID) -> Bool {
        overrides[studentID] != nil
    }

    /// Sets the default and drops the overrides that now agree with it.
    func setEveryone(_ choice: PresentationChoice) {
        everyone = choice
        overrides = overrides.filter { $0.value != choice }
    }

    func setEveryone(_ decision: CaptureFollowUp) {
        setEveryone(PresentationChoice(decision))
    }

    func setChoice(_ choice: PresentationChoice, for studentID: UUID) {
        overrides[studentID] = choice == everyone ? nil : choice
    }

    func setDecision(_ decision: CaptureFollowUp, for studentID: UUID) {
        setChoice(PresentationChoice(decision), for: studentID)
    }

    /// A chip tapped on the Everyone row.
    func tapEveryone(_ chip: CaptureFollowUp) {
        setEveryone(everyone.tapping(chip))
    }

    /// A chip tapped on one child's row.
    func tap(_ chip: CaptureFollowUp, for studentID: UUID) {
        setChoice(choice(for: studentID).tapping(chip), for: studentID)
    }

    /// Every child's decision, chosen or inherited.
    func decisions(for studentIDs: [UUID]) -> [UUID: CaptureFollowUp] {
        Dictionary(studentIDs.map { ($0, decision(for: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    /// Children whose decision differs from what they already have.
    func pendingDecisions(for studentIDs: [UUID]) -> [UUID: CaptureFollowUp] {
        var pending: [UUID: CaptureFollowUp] = [:]
        for id in studentIDs {
            let chosen = decision(for: id)
            if chosen != (applied[id]?.decision ?? .continueObserving) {
                pending[id] = chosen
            }
        }
        return pending
    }

    /// Children newly ready for the next lesson alongside their work, who
    /// weren't ready on the record.
    func newlyAlsoReady(for studentIDs: [UUID]) -> Set<UUID> {
        Set(studentIDs.filter { choice(for: $0).alsoReady && applied[$0]?.isReady != true })
    }

    /// Children Done would newly mark ready for the next lesson, on its own
    /// or alongside work: the ones the next lesson is planned for.
    func newlyReady(for studentIDs: [UUID]) -> Set<UUID> {
        Set(pendingDecisions(for: studentIDs).filter { $0.value == .readyForNextLesson }.map(\.key))
            .union(newlyAlsoReady(for: studentIDs))
    }

    /// Children ready on the record whom the guide no longer marks ready.
    func noLongerReady(for studentIDs: [UUID]) -> Set<UUID> {
        Set(studentIDs.filter { applied[$0]?.isReady == true && !choice(for: $0).isReady })
    }

    /// Whether Done would change any child's plan: a decision, or Ready for
    /// next turned on or off alongside work.
    func hasPendingPlans(for studentIDs: [UUID]) -> Bool {
        !pendingDecisions(for: studentIDs).isEmpty || !newlyAlsoReady(for: studentIDs).isEmpty
            || !noLongerReady(for: studentIDs).isEmpty
    }

    var checkInChanged: Bool { checkIn != loadedCheckIn }

    var hasNotes: Bool {
        !groupNote.trimmed().isEmpty || childNotes.values.contains { !$0.trimmed().isEmpty }
    }

    /// Whether Done would write anything.
    func hasChanges(for studentIDs: [UUID]) -> Bool {
        if hasNotes || hasPendingPlans(for: studentIDs) { return true }
        return checkInChanged && studentIDs.contains { decision(for: $0).createsWork }
    }

    /// What Done writes for these children.
    func commitInput(
        assignment: CDLessonAssignment,
        lesson: CDLesson,
        studentIDs: [UUID],
        lessons: [CDLesson]
    ) -> PresentationSessionCommit.Input {
        PresentationSessionCommit.Input(
            assignment: assignment,
            lesson: lesson,
            studentIDs: studentIDs,
            groupNote: groupNote,
            childNotes: childNotes,
            decisions: pendingDecisions(for: studentIDs),
            allDecisions: decisions(for: studentIDs),
            checkIn: checkIn,
            timedCheckIns: checkInDaysForDone,
            checkInMoved: checkInPicked || checkInChanged,
            lessons: lessons,
            followUpDetail: followUpDetail,
            alsoReady: newlyAlsoReady(for: studentIDs),
            noLongerReady: noLongerReady(for: studentIDs),
            nextLessonPlace: nextLessonPlace
        )
    }

    // MARK: - Loading

    /// Reads what the children already have and restores a Later draft, so a
    /// presentation reopened from Following shows where it was left.
    ///
    /// - Parameters:
    ///   - defaultDecision: the lesson's own rule — practice when its
    ///     progression rules require it, otherwise keep watching.
    ///   - timedCheckIns: each child's check-in day from
    ///     `PracticeCheckInTiming.checkInDays`. The sheet starts from them
    ///     when the record has no check-in day and no work yet; a Later draft
    ///     keeps the days it was left with, and a record already decided
    ///     keeps its own (Done moves an unchanged child's day only when the
    ///     guide moves the sheet's).
    func loadDecisions(
        studentIDs: [UUID],
        defaultDecision: CaptureFollowUp,
        timedCheckIns timing: [UUID: Date] = [:],
        context: NSManagedObjectContext,
        defaults: UserDefaults = .standard
    ) {
        let records = Self.appliedState(presentationID: presentationID, in: context)
        applied = records.choices
        loadedCheckIn = records.checkIn
        checkIn = records.checkIn
        checkInPicked = false
        timedCheckIns = [:]

        if let draft = PresentationSessionDraftStore.load(presentationID: presentationID, defaults: defaults) {
            everyone = PresentationChoice(rawValue: draft.everyone) ?? PresentationChoice(defaultDecision)
            overrides = Dictionary(draft.overrides.compactMap { key, value in
                guard let id = UUID(uuidString: key),
                      let choice = PresentationChoice(rawValue: value) else { return nil }
                return (id, choice)
            }, uniquingKeysWith: { first, _ in first })
            checkIn = PresentationCheckIn(day: draft.checkInDay)
            // Each child's own timed day, when Later kept them (none when
            // the guide had picked a day, which is then everyone's).
            for (key, day) in draft.timedCheckIns ?? [:] {
                guard let id = UUID(uuidString: key), studentIDs.contains(id) else { continue }
                timedCheckIns[id] = AppCalendar.startOfDay(day)
            }
            followUpDetail = draft.followUpDetail ?? ""
            // A day that has passed since Later is no longer a choice.
            if let day = draft.nextLessonPlace?.day, day < AppCalendar.startOfDay(Date()) {
                nextLessonPlace = nil
            } else {
                nextLessonPlace = draft.nextLessonPlace
            }
            return
        }

        // Nothing decided yet: practice comes back on the day chat would give
        // it, unless the guide picks another. A record already decided keeps
        // its day, so reopening it moves nothing nobody touched.
        let timed = timing.filter { studentIDs.contains($0.key) }
        if records.checkIn == .nextWorkCycle, !records.decisions.values.contains(where: \.createsWork),
           let earliest = timed.values.min() {
            timedCheckIns = timed.mapValues(AppCalendar.startOfDay)
            checkIn = PresentationCheckIn(day: earliest)
            loadedCheckIn = checkIn
        }

        let watching = PresentationChoice(.continueObserving)
        let onRecord = studentIDs.map { applied[$0] ?? watching }
        let anythingDecided = onRecord.contains { $0 != watching }
        if anythingDecided {
            // Reopened after Done: show each child as they stand.
            let first = onRecord.first ?? PresentationChoice(defaultDecision)
            everyone = onRecord.allSatisfy { $0 == first } ? first : PresentationChoice(defaultDecision)
            overrides = [:]
            for id in studentIDs {
                setChoice(applied[id] ?? watching, for: id)
            }
        } else {
            everyone = PresentationChoice(defaultDecision)
            overrides = [:]
        }
    }

    /// The decisions as a Later draft.
    var draft: PresentationSessionDraftStore.Draft {
        PresentationSessionDraftStore.Draft(
            everyone: everyone.rawValue,
            overrides: Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.uuidString, $0.value.rawValue) }),
            checkInDay: checkIn.day,
            followUpDetail: followUpDetail.trimmed().isEmpty ? nil : followUpDetail,
            nextLessonPlace: nextLessonPlace,
            savedAt: Date(),
            timedCheckIns: checkInDaysForDone.isEmpty
                ? nil
                : Dictionary(uniqueKeysWithValues: checkInDaysForDone.map { ($0.key.uuidString, $0.value) })
        )
    }

    /// Notes are saved by Later and Done; the fields start empty again.
    func clearNotes() {
        groupNote = ""
        childNotes = [:]
    }
}
