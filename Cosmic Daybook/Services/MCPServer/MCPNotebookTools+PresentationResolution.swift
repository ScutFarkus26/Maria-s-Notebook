//
//  MCPNotebookTools+PresentationResolution.swift
//  Cosmic Daybook
//
//  Which record a filed presentation belongs to, and whether the guide has
//  said why a child is having the lesson again.
//
//  Both questions are answered for each filing in a `record_presentation`
//  call after the filings before it are written, so a plan one filing
//  completes isn't claimed again by the next. A batch that names one child
//  who already has her lesson on record is still refused whole (nothing is
//  saved) rather than leaving the rest of the day filed around the refusal.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Where a Filed Presentation Lands

    /// Where the recorded presentation came from, so the receipt can tell the
    /// guide whether a plan was completed or a new record created.
    enum PresentationOrigin {
        case alreadyRecorded
        case plannedLesson
        case newRecord
    }

    /// One filing with its record chosen and the regive question answered.
    struct ResolvedFiling {
        let filing: PresentationFiling
        let assignment: CDLessonAssignment
        let origin: PresentationOrigin
        /// Named children the record already covers — empty unless this is a
        /// new record for a lesson some of them have had before.
        let conflicts: [RepeatConflict]
    }

    /// The app's one answer (`PresentationRecorder.resolvePlan`, domain logic
    /// review 2026-11-20, R12), shared with the command bar and Siri: a
    /// presentation of the lesson already given that day to these children (so
    /// re-filing the same account edits it rather than duplicating it), then a
    /// plan waiting for them (split off a larger one when it holds others too),
    /// and finally a new record.
    static func resolveAssignment(
        for filing: PresentationFiling, in modelContext: NSManagedObjectContext
    ) -> (assignment: CDLessonAssignment, origin: PresentationOrigin) {
        let resolved = PresentationRecorder.resolvePlan(
            lesson: filing.lesson, present: filing.students, on: filing.presentedAt, context: modelContext
        )
        let origin: PresentationOrigin = switch resolved.origin {
        case .alreadyRecorded: .alreadyRecorded
        case .plannedLesson: .plannedLesson
        case .newRecord: .newRecord
        }
        return (resolved.assignment, origin)
    }

    /// Records the filing's presentation on its day. One already given that
    /// day is an edit: it keeps its time and its children's follow-ups.
    static func record(
        _ resolved: ResolvedFiling, in modelContext: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        let origin: PresentationRecorder.PlanOrigin = switch resolved.origin {
        case .alreadyRecorded: .alreadyRecorded
        case .plannedLesson: .plannedLesson
        case .newRecord: .newRecord
        }
        return try PresentationRecorder.recordResolved(
            PresentationRecorder.ResolvedPlan(assignment: resolved.assignment, origin: origin),
            on: resolved.filing.presentedAt, context: modelContext
        )
    }

    // MARK: - The Regive Question

    /// Resolves the record and, for a genuinely new one, asks who already has
    /// the lesson.
    ///
    /// The other two origins are exempt by construction. `.alreadyRecorded` is
    /// the same lesson, children and day filed twice — an edit of that record,
    /// not a second giving. `.plannedLesson` completes a plan that passed this
    /// same guard when `schedule_presentation` made it; only a child added to
    /// a plan named by `planned_presentation_id` is asked (`takeOverPlan`).
    static func resolve(
        _ filing: PresentationFiling,
        index: PresentationRecordIndex,
        in modelContext: NSManagedObjectContext
    ) -> ResolvedFiling {
        // A plan named by id is taken over, whatever else is waiting.
        if let taken = takeOverPlan(filing, index: index, in: modelContext) { return taken }
        let resolved = resolveAssignment(for: filing, in: modelContext)
        let conflicts: [RepeatConflict] = resolved.origin == .newRecord
            ? repeatConflicts(
                lessonID: filing.lessonID.uuidString, students: filing.students,
                before: filing.presentedAt, index: index
            )
            : []
        return ResolvedFiling(
            filing: filing, assignment: resolved.assignment, origin: resolved.origin, conflicts: conflicts
        )
    }

    /// Refuses the whole call when any filing puts a lesson on a child's
    /// record for a second time without saying why. One error names every
    /// lesson it found, so the guide re-calls once rather than discovering the
    /// next one after each fix.
    static func refuseUnexplainedRepeats(_ resolved: [ResolvedFiling]) throws {
        let unexplained = resolved.filter { !$0.conflicts.isEmpty && $0.filing.purpose == nil }
        guard !unexplained.isEmpty else { return }
        throw refuseRepeat(tool: "record_presentation", unexplained.map {
            RepeatRefusal(
                lesson: $0.filing.lesson, conflicts: $0.conflicts, total: $0.filing.students.count
            )
        })
    }
}
