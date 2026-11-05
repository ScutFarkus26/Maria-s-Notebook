//
//  ReadyForNextEngine+PreviousLesson.swift
//  Cosmic Daybook
//
//  The previous lesson, as the guide wants to see it before giving the next
//  one (Danny, 2026-10-18): when it was given, how much work from it is still
//  open, what its last check-in said, how the last recall check went, and
//  whether it is mastered. And the one readiness rule that reads it, with the
//  previous lesson's own progression settings (`LessonProgressionRules`): a
//  lesson or sequence set not to require confirmation doesn't hold an
//  unconfirmed child back, as Presentations reads it (bug hunt 2026-11-03 #5).
//  Open work and a check-in asking for more practice stay worth a look
//  whatever the practice setting: in this rule they never hold a child back,
//  only ask for a look first (Simplify the app, Phase 3).
//
//  "Her work" is the Work column's rule, the one "work to show first" uses
//  (`WorkToShowFirst`): her own copy of linked work, or a shared row she is on
//  (`WorkVisibility`); a shared row is open for her until her own part is done
//  (`QuietStudentsOrder.openStudentIDs`). A classmate's copy that names her is
//  not hers. The last check-in is the status her latest closed row on the
//  lesson was logged with (`WorkLogService` closes a row with the check's
//  verdict). The last recall check is the latest one the guide ran, unless the
//  lesson was given to her again after it.
//
//  Cost: one fetch of the work on the lessons asked about that names one of
//  the children (two when a row names more than one child), and one of their
//  recall checks, for any number of children and lessons.
//

import CoreData
import Foundation

/// One child's previous lesson, for a row to show before the next one.
nonisolated struct PreviousLessonStatus: Sendable, Hashable {

    /// How the latest recall check the guide ran came back.
    enum Recall: Sendable, Hashable {
        case retained
        case shaky
        case forgotten
    }

    /// The previous lesson, as a UUID string.
    let lessonID: String
    /// The latest day it was given to her; nil for an undated mark.
    let lastGiven: Date?
    /// The guide confirmed her ready for the next lesson at capture.
    let confirmed: Bool
    /// A mastery mark. Confirmation is not mastery.
    let mastered: Bool
    /// Her pieces of work from the lesson that are still open.
    let openWorkCount: Int
    /// What her latest closed work on the lesson was logged as; nil when none
    /// is closed.
    let lastCheckIn: WorkStatus?
    /// The latest recall check since the lesson was last given; nil when none.
    let lastRecall: Recall?

    init(
        lessonID: String,
        lastGiven: Date? = nil,
        confirmed: Bool = false,
        mastered: Bool = false,
        openWorkCount: Int = 0,
        lastCheckIn: WorkStatus? = nil,
        lastRecall: Recall? = nil
    ) {
        self.lessonID = lessonID
        self.lastGiven = lastGiven
        self.confirmed = confirmed
        self.mastered = mastered
        self.openWorkCount = openWorkCount
        self.lastCheckIn = lastCheckIn
        self.lastRecall = lastRecall
    }

    /// "Given Oct 3 · 2 pieces of work open · Last check-in: Keep Practicing ·
    /// Not mastered yet": everything the guide asked to see, in one line.
    var summary: String {
        var parts: [String] = []
        if let lastGiven {
            parts.append("Given \(lastGiven.formatted(.dateTime.month(.abbreviated).day()))")
        } else {
            parts.append("Given, no date")
        }
        switch openWorkCount {
        case ...0: parts.append("No work open")
        case 1: parts.append("1 piece of work open")
        default: parts.append("\(openWorkCount) pieces of work open")
        }
        if let lastCheckIn {
            parts.append("Last check-in: \(lastCheckIn.displayName)")
        }
        parts.append(mastered ? "Mastered" : "Not mastered yet")
        return parts.joined(separator: " · ")
    }
}

/// The readiness level and the plain reasons behind it.
nonisolated struct ReadinessVerdict: Sendable, Hashable {
    let tier: ReadinessTier
    /// Empty when ready.
    let reasons: [String]
}

// MARK: - The Rule

nonisolated extension ReadyForNextEngine {

    /// Both gates on: the built-in rule, for a lesson with no settings of its own.
    static let bothGates = LessonProgressionRules.ResolvedRules(
        requiresPractice: true, requiresTeacherConfirmation: true, source: .builtInDefault
    )

    /// The one readiness rule, under the previous lesson's `rules`.
    ///
    /// - Ready: the previous lesson is confirmed or mastered, no work from it
    ///   is open, and its last check-in didn't ask for more practice.
    /// - Ready, check first (`.almostReady`): confirmed or mastered, but work
    ///   is open, the last check-in asked for more practice, or the last
    ///   recall check was shaky or forgotten; one reason each.
    /// - Not ready yet: not confirmed or mastered.
    ///
    /// A lesson that doesn't require confirmation needs neither. The practice
    /// setting changes nothing here: open work and a check-in asking for more
    /// are reasons to look first, never a hold.
    static func readiness(
        of previous: PreviousLessonStatus,
        rules: LessonProgressionRules.ResolvedRules = ReadyForNextEngine.bothGates
    ) -> ReadinessVerdict {
        guard previous.confirmed || previous.mastered || !rules.requiresTeacherConfirmation else {
            return ReadinessVerdict(tier: .notReady, reasons: ["Not confirmed yet"])
        }
        var reasons: [String] = []
        if previous.openWorkCount > 0 {
            reasons.append(openWorkReason(previous.openWorkCount))
        }
        if previous.lastCheckIn == .keepPracticing {
            reasons.append(practiceAskedReason)
        }
        switch previous.lastRecall {
        case .shaky: reasons.append(shakyRecallReason)
        case .forgotten: reasons.append(forgottenRecallReason)
        case .retained, nil: break
        }
        return ReadinessVerdict(tier: reasons.isEmpty ? .ready : .almostReady, reasons: reasons)
    }

    /// "1 piece of work still open", "2 pieces of work still open".
    static func openWorkReason(_ count: Int) -> String {
        count == 1 ? "1 piece of work still open" : "\(count) pieces of work still open"
    }

    static let practiceAskedReason = "Last check-in: needs more practice"
    static let shakyRecallReason = "Recall check was shaky"
    static let forgottenRecallReason = "Recall check: needs the lesson again"
}

// MARK: - The Lesson's Own Settings

/// Each previous lesson's progression rules, resolved as Presentations resolves
/// them (`LessonProgressionRules`: the lesson's override, then its sequence's
/// settings, then both gates on), with one settings fetch per sequence for a
/// whole grid or queue.
@MainActor
final class ProgressionRulesLookup {
    private let context: NSManagedObjectContext
    private var settings: [String: CDLessonSequenceSettings?] = [:]
    private var resolved: [NSManagedObjectID: LessonProgressionRules.ResolvedRules] = [:]

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    func rules(for lesson: CDLesson) -> LessonProgressionRules.ResolvedRules {
        if let known = resolved[lesson.objectID] { return known }
        // The sequence's settings matter only when a gate inherits them.
        let inherits = lesson.practiceOverride == .inherit || lesson.confirmationOverride == .inherit
        let found = inherits ? sequenceSettings(area: lesson.area, sequence: lesson.sequence) : nil
        let rules = LessonProgressionRules.resolve(for: lesson) { found }
        resolved[lesson.objectID] = rules
        return rules
    }

    private func sequenceSettings(area: String, sequence: String) -> CDLessonSequenceSettings? {
        let key = "\(area.lowercased())|\(sequence.lowercased())"
        if let cached = settings[key] { return cached }
        let found = CDLessonSequenceSettings.find(area: area, sequence: sequence, context: context)
        settings[key] = .some(found)
        return found
    }
}

// MARK: - Reading It

/// The work and recall checks behind `PreviousLessonStatus`, read once for
/// many children and lessons.
@MainActor
struct PreviousLessonRecord {

    /// One child on one previous lesson, both as UUID strings.
    nonisolated struct Pair: Hashable, Sendable {
        let studentID: String
        let lessonID: String
    }

    private struct WorkFacts {
        var open = 0
        var lastClosed: ClosedRow?
    }

    /// A closed row, by when it closed (its id breaks a tie).
    private struct ClosedRow {
        let date: Date
        let id: String
        let status: WorkStatus

        func isLater(than other: ClosedRow) -> Bool {
            date != other.date ? date > other.date : id > other.id
        }
    }

    private struct RecallFact {
        let date: Date
        let outcome: PreviousLessonStatus.Recall
    }

    private let work: [Pair: WorkFacts]
    private let recall: [Pair: RecallFact]

    init(pairs: [Pair], in context: NSManagedObjectContext) {
        let wanted = Set(pairs)
        let studentIDs = Set(pairs.map(\.studentID))
        let lessonIDs = Set(pairs.map(\.lessonID))
        guard !wanted.isEmpty else {
            work = [:]
            recall = [:]
            return
        }
        work = Self.readWork(wanted: wanted, studentIDs: studentIDs, lessonIDs: lessonIDs, in: context)
        recall = Self.readRecall(wanted: wanted, studentIDs: studentIDs, lessonIDs: lessonIDs, in: context)
    }

    /// Her previous-lesson status, from what the record index holds for her
    /// on the lesson (`given`) and the work and recall read here.
    func status(
        student studentID: String, lesson lessonID: String, given: PresentationRecordIndex.Given?
    ) -> PreviousLessonStatus {
        let pair = Pair(studentID: studentID, lessonID: lessonID)
        let facts = work[pair]
        let lastGiven = given?.days.last
        // A recall check made before she was last given the lesson was about
        // the old giving; the lesson has been taught again since.
        let recallFact = recall[pair].flatMap { fact -> RecallFact? in
            guard let lastGiven, AppCalendar.startOfDay(fact.date) < AppCalendar.startOfDay(lastGiven) else {
                return fact
            }
            return nil
        }
        return PreviousLessonStatus(
            lessonID: lessonID,
            lastGiven: lastGiven,
            confirmed: given?.confirmed ?? false,
            mastered: given?.mastered ?? false,
            openWorkCount: facts?.open ?? 0,
            lastCheckIn: facts?.lastClosed?.status,
            lastRecall: recallFact?.outcome
        )
    }

    // MARK: - Work

    private static func readWork(
        wanted: Set<Pair>, studentIDs: Set<String>, lessonIDs: Set<String>, in context: NSManagedObjectContext
    ) -> [Pair: WorkFacts] {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "lessonID IN %@", Array(lessonIDs)),
            NSCompoundPredicate(orPredicateWithSubpredicates: [
                NSPredicate(format: "studentID IN %@", Array(studentIDs)),
                NSPredicate(format: "ANY participants.studentID IN %@", Array(studentIDs))
            ])
        ])
        request.relationshipKeyPathsForPrefetching = ["participants"]
        let rows = context.safeFetch(request).filter { !$0.isDeleted }
        guard !rows.isEmpty else { return [:] }
        // A row naming several children is told apart from a set of linked
        // copies by the other rows on its lesson, read here in one more fetch.
        let visibility = WorkVisibility(covering: rows, in: context)

        var facts: [Pair: WorkFacts] = [:]
        for row in rows {
            let openFor = row.status.isOpen ? QuietStudentsOrder.openStudentIDs(of: row, visibility: visibility) : []
            for child in WorkGrouping.studentIDs(of: row) {
                let pair = Pair(studentID: child.uuidString, lessonID: row.lessonID)
                guard wanted.contains(pair), visibility.isVisible(row, to: child) else { continue }
                var fact = facts[pair] ?? WorkFacts()
                if openFor.contains(child) {
                    fact.open += 1
                } else if row.status.isClosed {
                    let closed = ClosedRow(
                        date: row.completedAt ?? row.lastTouchedAt ?? row.createdAt ?? .distantPast,
                        id: row.id?.uuidString ?? "",
                        status: row.status
                    )
                    if fact.lastClosed.map({ closed.isLater(than: $0) }) ?? true {
                        fact.lastClosed = closed
                    }
                }
                facts[pair] = fact
            }
        }
        return facts
    }

    // MARK: - Recall

    private static func readRecall(
        wanted: Set<Pair>, studentIDs: Set<String>, lessonIDs: Set<String>, in context: NSManagedObjectContext
    ) -> [Pair: RecallFact] {
        let request = CDFetchRequest(CDLessonRecallCheck.self)
        // Only checks the guide ran: a "covered" row is inferred from a later
        // lesson, and only ever says retained.
        request.predicate = NSPredicate(
            format: "studentID IN %@ AND lessonID IN %@ AND sourceRaw == %@",
            Array(studentIDs), Array(lessonIDs), RecallSource.observed.rawValue
        )
        var latest: [Pair: RecallFact] = [:]
        for check in context.safeFetch(request) where !check.isDeleted {
            let pair = Pair(studentID: check.studentID, lessonID: check.lessonID)
            guard wanted.contains(pair) else { continue }
            let date = check.checkedAt ?? check.createdAt ?? .distantPast
            if let current = latest[pair], current.date >= date { continue }
            latest[pair] = RecallFact(date: date, outcome: outcome(check.outcome))
        }
        return latest
    }

    private static func outcome(_ outcome: RecallOutcome) -> PreviousLessonStatus.Recall {
        switch outcome {
        case .retained: .retained
        case .shaky: .shaky
        case .forgotten: .forgotten
        }
    }
}
