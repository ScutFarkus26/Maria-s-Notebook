// PresentationRecorder+ResolvePlan.swift
// Which presentation a lesson given to these children on this day lands on
// (domain logic review 2026-11-20, R12). Claude's `record_presentation`, the
// command bar's capture and Siri's Mark Lesson Presented each had their own
// copy: Claude matched the exact children and treated the same day as an edit,
// the command bar had no same-day check (saving one capture twice made two
// presentations), and Siri took any waiting plan holding the child, so a
// second "presented" made a second record. The sheet starts from the plan it
// is open on and takes the absent children off (`record`). Now the other three
// ask this, in one order:
//
//  1. The same day is an edit: a presentation of the lesson already given
//     that day to these children (exactly, then any one that holds them all).
//  2. A plan waiting for exactly these children, a dated one first, then the
//     newest.
//  3. A plan waiting for them and others: they are split off it onto their
//     own record, and the others keep the plan, its day and its notes, as
//     the children who weren't there do on the sheet.
//  4. A new record.
//
// `recordResolved` then records it: a presentation already given that day
// keeps its time and its children's follow-ups, so filing it again edits it.
// Nothing saves here; the caller owns the save.

import CoreData
import Foundation

extension PresentationRecorder {

    /// Where `resolvePlan` found the record.
    enum PlanOrigin: Equatable {
        /// Already given that day: filing again edits it.
        case alreadyRecorded
        /// A plan waiting to be given, theirs alone or split off a larger one.
        case plannedLesson
        /// Nothing waiting: a new draft, inserted and not yet recorded.
        case newRecord
    }

    struct ResolvedPlan {
        let assignment: CDLessonAssignment
        let origin: PlanOrigin
    }

    /// The record a lesson given to `present` on `day` belongs on. See the file header.
    static func resolvePlan(
        lesson: CDLesson, present: [CDStudent], on day: Date, context: NSManagedObjectContext
    ) -> ResolvedPlan {
        let ids = Set(present.compactMap(\.id))
        guard let lessonID = lesson.id, !ids.isEmpty else {
            return ResolvedPlan(assignment: newRecord(lesson, present, context), origin: .newRecord)
        }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        let all = context.safeFetch(request).filter { !$0.isDeleted }

        // 1. The same day.
        let sameDay = all.filter { assignment in
            guard assignment.isPresented, let given = assignment.presentedAt else { return false }
            return AppCalendar.shared.isDate(given, inSameDayAs: day)
                && ids.isSubset(of: Set(assignment.resolvedStudentIDs))
        }
        if let given = sameDay.first(where: { Set($0.resolvedStudentIDs) == ids }) ?? sameDay.first {
            return ResolvedPlan(assignment: given, origin: .alreadyRecorded)
        }

        // 2 and 3. A plan waiting.
        let waiting = all.filter { !$0.isPresented }.sorted { lhs, rhs in
            if lhs.isScheduled != rhs.isScheduled { return lhs.isScheduled }
            return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
        }
        if let plan = waiting.first(where: { Set($0.resolvedStudentIDs) == ids }) {
            return ResolvedPlan(assignment: plan, origin: .plannedLesson)
        }
        if let larger = waiting.first(where: { ids.isStrictSubset(of: Set($0.resolvedStudentIDs)) }),
           let split = PresentationSplitService.splitReadyStudents(
               from: larger, readyStudentIDs: present.compactMap(\.id), asDraft: true, context: context
           ) {
            return ResolvedPlan(assignment: split, origin: .plannedLesson)
        }

        // 4. A new record.
        return ResolvedPlan(assignment: newRecord(lesson, present, context), origin: .newRecord)
    }

    /// Records what `resolvePlan` found as given on `day`. One already given
    /// that day keeps its time, and its children's follow-ups stay as they
    /// are; only a child it names with no history row yet gets one.
    @discardableResult
    static func recordResolved(
        _ resolved: ResolvedPlan, on day: Date, context: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        let edit = resolved.origin == .alreadyRecorded
        return try LifecycleService.recordPresentation(
            from: resolved.assignment,
            presentedAt: edit ? (resolved.assignment.presentedAt ?? day) : day,
            modelContext: context,
            followExistingRows: !edit
        )
    }

    private static func newRecord(
        _ lesson: CDLesson, _ present: [CDStudent], _ context: NSManagedObjectContext
    ) -> CDLessonAssignment {
        PresentationFactory.makeDraft(lesson: lesson, students: present, context: context)
    }
}
