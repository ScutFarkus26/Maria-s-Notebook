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

    func outcome(for studentID: UUID?) -> RolloverOutcome {
        guard let studentID else { return .stay }
        return outcomes[studentID] ?? .stay
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
        }
        return result
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
        if changed > 0 {
            context.safeSave()
        }
        return changed
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
