//
//  MCPNotebookTools+PresentationResolution.swift
//  Cosmic Daybook
//
//  Which record a filed presentation belongs to, and whether the guide has
//  said why a child is having the lesson again.
//
//  Both questions are answered for every filing in a `record_presentation`
//  call before a single one is written, so a batch that names one child who
//  already has her lesson on record is refused whole rather than leaving the
//  rest of the day filed around the refusal.
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

    /// Prefers a presentation already recorded for this lesson, these students
    /// and this day (so re-filing the same account edits it rather than
    /// duplicating it), then a plan waiting to be given, and finally a new
    /// record — mirroring the command bar's `resolvePresentation`.
    static func resolveAssignment(
        for filing: PresentationFiling, in modelContext: NSManagedObjectContext
    ) -> (assignment: CDLessonAssignment, origin: PresentationOrigin) {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", filing.lessonID.uuidString)
        let expected = Set(filing.studentIDs)
        let candidates = modelContext.safeFetch(request).filter { Set($0.resolvedStudentIDs) == expected }

        if let sameDay = candidates.first(where: { assignment in
            guard assignment.isPresented, let recordedAt = assignment.presentedAt else { return false }
            return AppCalendar.shared.isDate(recordedAt, inSameDayAs: filing.presentedAt)
        }) {
            return (sameDay, .alreadyRecorded)
        }

        let planned = candidates
            .filter { !$0.isPresented }
            .sorted {
                if $0.isScheduled != $1.isScheduled { return $0.isScheduled }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            .first
        if let planned {
            return (planned, .plannedLesson)
        }

        return (
            PresentationFactory.makeDraft(
                lesson: filing.lesson, students: filing.students, context: modelContext
            ),
            .newRecord
        )
    }

    // MARK: - The Regive Question

    /// Resolves the record and, for a genuinely new one, asks who already has
    /// the lesson.
    ///
    /// The other two origins are exempt by construction. `.alreadyRecorded` is
    /// the same lesson, children and day filed twice — an edit of that record,
    /// not a second giving. `.plannedLesson` completes a plan that passed this
    /// same guard when `schedule_presentation` made it.
    static func resolve(
        _ filing: PresentationFiling,
        index: PresentationRecordIndex,
        in modelContext: NSManagedObjectContext
    ) -> ResolvedFiling {
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
