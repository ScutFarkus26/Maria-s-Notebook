// RolloverService.swift
// Applies a school-year rollover: per-student outcomes (stay / promote / transfer /
// withdraw) written in one atomic save, with optional auto-logged observations.

import Foundation
import CoreData

// MARK: - Plan Types

/// Per-student outcome chosen in the school-year rollover flow.
enum RolloverOutcome: Hashable {
    case stay
    case promote(to: CDStudent.Level)
    case transfer
    case withdraw

    /// Short label for menus and summary lists.
    var label: String {
        switch self {
        case .stay: return "Stay"
        case .promote(let target): return "Promote to \(target.rawValue)"
        case .transfer: return "Transfer Out"
        case .withdraw: return "Withdraw"
        }
    }
}

/// The complete rollover to apply: one outcome per student (missing = stay),
/// a shared effective date, and whether to log an observation for each change.
struct RolloverPlan {
    var outcomes: [UUID: RolloverOutcome] = [:]
    var effectiveDate: Date = Date()
    var writeNotes: Bool = true
    /// What to do with each child's year-plan entries left over from the
    /// outgoing year (missing = leave them alone).
    var carryOver: [UUID: YearPlanCarryOverChoice] = [:]
    /// The day a re-dated run starts from. nil ⇒ the first open day of the
    /// incoming year, which is what the caller passes to `apply`.
    var carryOverLanding: Date?

    func outcome(for studentID: UUID?) -> RolloverOutcome {
        guard let studentID else { return .stay }
        return outcomes[studentID] ?? .stay
    }

    func carryOverChoice(for studentID: UUID?) -> YearPlanCarryOverChoice {
        guard let studentID else { return .leave }
        return carryOver[studentID] ?? .leave
    }
}

/// Counts shown in the review step and the applied confirmation.
struct RolloverSummary: Equatable {
    /// Keyed by the promotion *target* level.
    var promoted: [CDStudent.Level: Int] = [:]
    var transferred = 0
    var withdrawn = 0
    var staying = 0
    /// Lessons planned but not yet given that name a departing child; the
    /// rollover takes those children off them so the plans stop generating
    /// work for children who have left.
    var futurePlansForDeparting = 0
    /// Year-plan entries still pencilled in for departing children; the
    /// rollover marks these skipped so they stop accruing behind pace.
    var yearPlanEntriesForDeparting = 0
    /// Entries belonging to children who are staying or being promoted whose
    /// targets fell in the outgoing year — last year's intentions.
    var carriedOverEntries = 0
    /// How many of those the plan re-dates, and how many it skips.
    var carriedOverToRedate = 0
    var carriedOverToSkip = 0
    /// How many children carry entries over at all, and how many each choice
    /// touches — the review states the two actions separately.
    var carriedOverByStudent = 0
    var carriedOverRedateChildren = 0
    var carriedOverSkipChildren = 0

    var changeCount: Int { promoted.values.reduce(0, +) + transferred + withdrawn }

    /// "2 promoted to Upper · 7 promoted to Adolescent · 12 transferred · 1 withdrawn · 11 stay"
    var text: String {
        var parts: [String] = []
        for level in CDStudent.Level.allCases {
            if let count = promoted[level], count > 0 {
                parts.append("\(count) promoted to \(level.rawValue)")
            }
        }
        if transferred > 0 { parts.append("\(transferred) transferred") }
        if withdrawn > 0 { parts.append("\(withdrawn) withdrawn") }
        parts.append("\(staying) stay")
        return parts.joined(separator: " · ")
    }

    /// Counts the carried-over entries belonging to children who are staying or
    /// being promoted, split by the choice made for each. Departing children
    /// are excluded on purpose: their whole plan is skipped by the departure
    /// cascade, and counting it here twice would make the review lie.
    fileprivate mutating func addCarryOverCounts(
        for plan: RolloverPlan, students: [CDStudent], context: NSManagedObjectContext
    ) {
        let yearStart = YearPlanStaleness.currentYearStart()
        for studentID in RolloverService.continuingStudentIDs(in: plan, students: students) {
            let count = YearPlanCarryOver.entries(for: studentID, in: context, yearStart: yearStart).count
            guard count > 0 else { continue }
            carriedOverEntries += count
            carriedOverByStudent += 1
            switch plan.carryOverChoice(for: studentID) {
            case .leave:
                continue
            case .redate:
                carriedOverToRedate += count
                carriedOverRedateChildren += 1
            case .skip:
                carriedOverToSkip += count
                carriedOverSkipChildren += 1
            }
        }
    }
}

// MARK: - Service

enum RolloverService {

    /// Pure summary of what a plan would do to the given roster. Pass a
    /// context to also count the planned lessons departing children are on.
    static func summary(
        for plan: RolloverPlan, students: [CDStudent], context: NSManagedObjectContext? = nil
    ) -> RolloverSummary {
        var result = RolloverSummary()
        for student in students {
            switch plan.outcome(for: student.id) {
            case .stay:
                result.staying += 1
            case .promote(let target):
                result.promoted[target, default: 0] += 1
            case .transfer:
                result.transferred += 1
            case .withdraw:
                result.withdrawn += 1
            }
        }
        if let context {
            let departing = departingStudentIDs(in: plan, students: students)
            result.futurePlansForDeparting = StudentDeparturePlans
                .futurePlans(for: departing, in: context)
                .count
            result.yearPlanEntriesForDeparting = StudentDeparturePlans
                .plannedEntries(for: departing, in: context)
                .count
            result.addCarryOverCounts(for: plan, students: students, context: context)
        }
        return result
    }

    /// Children staying or being promoted — the only ones a carry-over choice
    /// applies to. A departing child's whole plan is skipped by the departure
    /// cascade, and that decision wins.
    static func continuingStudentIDs(in plan: RolloverPlan, students: [CDStudent]) -> [UUID] {
        students.compactMap { student in
            switch plan.outcome(for: student.id) {
            case .stay, .promote: return student.id
            case .transfer, .withdraw: return nil
            }
        }
    }

    static func departingStudentIDs(in plan: RolloverPlan, students: [CDStudent]) -> [UUID] {
        students.compactMap { student in
            switch plan.outcome(for: student.id) {
            case .transfer, .withdraw: return student.id
            case .stay, .promote: return nil
            }
        }
    }

    /// Applies the plan in a single context save (atomic: everything lands or nothing does).
    /// Returns the number of students changed.
    @discardableResult
    static func apply(
        _ plan: RolloverPlan,
        students: [CDStudent],
        incomingYearLabel: String,
        carryOverLanding: Date? = nil,
        context: NSManagedObjectContext
    ) -> Int {
        var changed = 0
        for student in students {
            let outcome = plan.outcome(for: student.id)
            // The note describes the move, so build it before mutating the level.
            let noteBody = noteBody(for: outcome, student: student, incomingYearLabel: incomingYearLabel)

            switch outcome {
            case .stay:
                continue
            case .promote(let target):
                guard target != student.level else { continue }
                student.previousLevelRaw = student.levelRaw
                student.level = target
                student.dateLastPromoted = plan.effectiveDate
            case .transfer:
                student.enrollmentStatus = .transferred
                student.dateWithdrawn = plan.effectiveDate
                retractFuturePlans(for: student, context: context)
            case .withdraw:
                student.enrollmentStatus = .withdrawn
                student.dateWithdrawn = plan.effectiveDate
                retractFuturePlans(for: student, context: context)
            }
            student.modifiedAt = Date()
            changed += 1

            if plan.writeNotes, let noteBody, let studentID = student.id {
                makeNote(body: noteBody, studentID: studentID, date: plan.effectiveDate, context: context)
            }
        }
        // After the student loop, so a departing child's entries are already
        // skipped by the departure cascade and are never re-dated first.
        let carried = applyCarryOver(
            plan, students: students,
            landing: carryOverLanding ?? plan.carryOverLanding ?? Date(),
            context: context
        )
        if changed > 0 || carried > 0 {
            context.safeSave()
        }
        return changed
    }

    /// Applies each continuing child's carry-over choice. Returns how many
    /// entries were moved or skipped. Does not save.
    @discardableResult
    private static func applyCarryOver(
        _ plan: RolloverPlan,
        students: [CDStudent],
        landing: Date,
        context: NSManagedObjectContext
    ) -> Int {
        let yearStart = YearPlanStaleness.currentYearStart()
        var touched = 0
        for studentID in continuingStudentIDs(in: plan, students: students) {
            let choice = plan.carryOverChoice(for: studentID)
            guard choice != .leave else { continue }
            let entries = YearPlanCarryOver.entries(for: studentID, in: context, yearStart: yearStart)
            guard !entries.isEmpty else { continue }
            switch choice {
            case .leave:
                continue
            case .redate:
                touched += YearPlanCarryOver.redate(entries, landingOn: landing, in: context)
            case .skip:
                touched += YearPlanCarryOver.skip(entries)
            }
        }
        return touched
    }

    /// A child who has left should not be on lessons still to be given —
    /// those plans generate work naming her when they are presented — nor
    /// should her year plan keep pencilling in lessons she will not be here
    /// for. The entries are skipped, not deleted, so a return finds them.
    private static func retractFuturePlans(for student: CDStudent, context: NSManagedObjectContext) {
        guard let studentID = student.id else { return }
        let plans = StudentDeparturePlans.futurePlans(for: studentID, in: context)
        StudentDeparturePlans.retract(studentID: studentID, from: plans, in: context)
        StudentDeparturePlans.skip(entries: StudentDeparturePlans.plannedEntries(for: studentID, in: context))
    }

    // MARK: - Notes

    private static func noteBody(
        for outcome: RolloverOutcome,
        student: CDStudent,
        incomingYearLabel: String
    ) -> String? {
        switch outcome {
        case .stay:
            return nil
        case .promote(let target):
            guard target != student.level else { return nil }
            return "Promoted from \(student.level.rawValue) to \(target.rawValue) "
                + "for the \(incomingYearLabel) school year."
        case .transfer:
            return "Transferred to another class at the end of the school year "
                + "(before \(incomingYearLabel))."
        case .withdraw:
            return "Withdrawn at the end of the school year (before \(incomingYearLabel))."
        }
    }

    /// Mirrors the presentation-outcome note path: a student-scoped observation,
    /// flagged for reports so departing students always have report content.
    private static func makeNote(
        body: String,
        studentID: UUID,
        date: Date,
        context: NSManagedObjectContext
    ) {
        let note = CDNote(context: context)
        note.body = body
        note.scope = .student(studentID)
        // Date the note at the transition itself so it lands in the outgoing year's timeline.
        note.createdAt = date
        note.updatedAt = date
        note.includeInReport = true
        note.syncStudentLinks(in: context)
    }
}
