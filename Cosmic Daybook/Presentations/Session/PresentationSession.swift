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
    /// The Everyone row's decision; each child inherits it unless overridden.
    private(set) var everyone: CaptureFollowUp = .continueObserving
    private(set) var overrides: [UUID: CaptureFollowUp] = [:]
    var checkIn: PresentationCheckIn = .nextWorkCycle
    /// What each child already has on record, read when the beat opens.
    private(set) var applied: [UUID: CaptureFollowUp] = [:]
    private(set) var loadedCheckIn: PresentationCheckIn = .nextWorkCycle
    /// Set once Done or Later has handled the session, so closing the sheet
    /// afterwards does nothing more.
    private(set) var isFinished = false

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
    }

    func showWho() {
        phase = .who
    }

    func markFinished() {
        isFinished = true
    }

    // MARK: - Decisions

    func decision(for studentID: UUID) -> CaptureFollowUp {
        overrides[studentID] ?? everyone
    }

    func isOverridden(_ studentID: UUID) -> Bool {
        overrides[studentID] != nil
    }

    /// Sets the default and drops the overrides that now agree with it.
    func setEveryone(_ decision: CaptureFollowUp) {
        everyone = decision
        overrides = overrides.filter { $0.value != decision }
    }

    func setDecision(_ decision: CaptureFollowUp, for studentID: UUID) {
        overrides[studentID] = decision == everyone ? nil : decision
    }

    /// Children whose decision differs from what they already have.
    func pendingDecisions(for studentIDs: [UUID]) -> [UUID: CaptureFollowUp] {
        var pending: [UUID: CaptureFollowUp] = [:]
        for id in studentIDs {
            let chosen = decision(for: id)
            if chosen != (applied[id] ?? .continueObserving) {
                pending[id] = chosen
            }
        }
        return pending
    }

    var checkInChanged: Bool { checkIn != loadedCheckIn }

    var hasNotes: Bool {
        !groupNote.trimmed().isEmpty || childNotes.values.contains { !$0.trimmed().isEmpty }
    }

    /// Whether Done would write anything.
    func hasChanges(for studentIDs: [UUID]) -> Bool {
        if hasNotes || !pendingDecisions(for: studentIDs).isEmpty { return true }
        return checkInChanged && studentIDs.contains { decision(for: $0).createsWork }
    }

    // MARK: - Loading

    /// Reads what the children already have and restores a Later draft, so a
    /// presentation reopened from Following shows where it was left.
    ///
    /// - Parameter defaultDecision: the lesson's own rule — practice when its
    ///   progression rules require it, otherwise keep watching.
    func loadDecisions(
        studentIDs: [UUID],
        defaultDecision: CaptureFollowUp,
        context: NSManagedObjectContext,
        defaults: UserDefaults = .standard
    ) {
        let records = Self.appliedState(presentationID: presentationID, in: context)
        applied = records.decisions
        loadedCheckIn = records.checkIn
        checkIn = records.checkIn

        if let draft = PresentationSessionDraftStore.load(presentationID: presentationID, defaults: defaults) {
            everyone = CaptureFollowUp(rawValue: draft.everyone) ?? defaultDecision
            overrides = Dictionary(uniqueKeysWithValues: draft.overrides.compactMap { key, value in
                guard let id = UUID(uuidString: key),
                      let decision = CaptureFollowUp(rawValue: value) else { return nil }
                return (id, decision)
            })
            checkIn = PresentationCheckIn(day: draft.checkInDay)
            return
        }

        let onRecord = studentIDs.map { applied[$0] ?? .continueObserving }
        let anythingDecided = onRecord.contains { $0 != .continueObserving }
        if anythingDecided {
            // Reopened after Done: show each child as they stand.
            let first = onRecord.first ?? defaultDecision
            everyone = onRecord.allSatisfy { $0 == first } ? first : defaultDecision
            overrides = [:]
            for id in studentIDs {
                setDecision(applied[id] ?? .continueObserving, for: id)
            }
        } else {
            everyone = defaultDecision
            overrides = [:]
        }
    }

    /// The decisions as a Later draft.
    var draft: PresentationSessionDraftStore.Draft {
        PresentationSessionDraftStore.Draft(
            everyone: everyone.rawValue,
            overrides: Dictionary(uniqueKeysWithValues: overrides.map { ($0.key.uuidString, $0.value.rawValue) }),
            checkInDay: checkIn.day,
            savedAt: Date()
        )
    }

    /// Notes are saved by Later and Done; the fields start empty again.
    func clearNotes() {
        groupNote = ""
        childNotes = [:]
    }

    // MARK: - Reading the records

    struct AppliedState: Equatable {
        var decisions: [UUID: CaptureFollowUp]
        var checkIn: PresentationCheckIn
    }

    /// Each child's standing decision, read from her follow-up row and the work
    /// this presentation gave her: a resolved re-present or next-lesson row,
    /// open practice or follow-up work, and otherwise keep watching.
    static func appliedState(presentationID: UUID, in context: NSManagedObjectContext) -> AppliedState {
        let rows = PresentationFollowUpService.rows(for: presentationID, in: context)
        let workRequest = CDFetchRequest(CDWorkModel.self)
        workRequest.predicate = NSPredicate(format: "presentationID == %@", presentationID.uuidString)
        let openWork = context.safeFetch(workRequest).filter { $0.status.isOpen }
        let workByStudent = Dictionary(grouping: openWork, by: \.studentID)

        var decisions: [UUID: CaptureFollowUp] = [:]
        var checkInDay: Date?
        for row in rows {
            guard let studentID = UUID(uuidString: row.studentID) else { continue }
            if row.followUpResolvedAt != nil, let resolution = row.followUpResolution {
                switch resolution {
                case .supportOrRepresent: decisions[studentID] = .represent
                case .readyForNextPresentation: decisions[studentID] = .readyForNextLesson
                case .continueIndependentWork, .noFurtherFollowUp: decisions[studentID] = .continueObserving
                }
                continue
            }
            let kinds = Set((workByStudent[row.studentID] ?? []).compactMap(\.kind))
            if kinds.contains(.practiceLesson) {
                decisions[studentID] = .practice
            } else if kinds.contains(.followUpAssignment) {
                decisions[studentID] = .followUpWork
            } else {
                decisions[studentID] = .continueObserving
            }
            if checkInDay == nil, row.hasOpenFollowUp, row.followUpAction == .checkWork {
                checkInDay = row.followUpReviewAt
            }
        }
        return AppliedState(decisions: decisions, checkIn: PresentationCheckIn(day: checkInDay))
    }
}
