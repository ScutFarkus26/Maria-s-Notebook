//
//  PresentationPlanner.swift
//  Cosmic Daybook
//
//  Planning a lesson from a picker, with the reason when it is a regive.
//
//  Three surfaces now put a draft in the inbox from a lesson and a set of
//  children — the lessons list, the presentations overview and Today's ready
//  queue — and all three have to file a repeat the way the MCP tools do: a
//  second pass marks the child's previous record for re-teaching, and either
//  purpose opens the new draft's notes with the purpose line that
//  `student_presentation_history` reads back as "(2nd time; second pass)".
//
//  `planOrReuse` adds the check every path shares, that a child already
//  waiting for the lesson isn't planned for it twice (bug hunt 2026-10-12, #32).
//
//  The note line is never written by hand here. It comes from
//  `RepeatPurpose.noteLine`, through `MCPNotebookTools.recordRepeatIntent`, so
//  the in-app path and the tool path cannot drift apart.
//

import CoreData
import Foundation

/// Why a lesson is being given to a child who already has it. The same two
/// words the MCP tools take, so the app and the tools file a repeat alike.
typealias RepeatPurpose = MCPNotebookTools.RepeatPurpose

enum PresentationPlanner {

    /// Files the draft, and writes the repeat's reason onto it when the guide
    /// gave one.
    ///
    /// The record is read *before* the draft is inserted, so the new row is
    /// never part of the index the repeat is judged against.
    ///
    /// - Returns: the draft, or nil when there is nobody or no lesson to plan.
    @discardableResult
    static func planDraft(
        lesson: CDLesson,
        students: [CDStudent],
        purpose: RepeatPurpose?,
        plannedOn day: Date = Date(),
        in context: NSManagedObjectContext
    ) -> CDLessonAssignment? {
        guard !students.isEmpty, let lessonUUID = lesson.id else { return nil }
        let lessonID: String = lessonUUID.uuidString
        var index: PresentationRecordIndex?
        if purpose != nil {
            let scope: Set<String> = [lessonID]
            index = PresentationRecordIndex(lessonIDs: scope, in: context)
        }

        let draft: CDLessonAssignment = PresentationFactory.makeDraft(
            lesson: lesson, students: students, context: context
        )

        if let purpose, let index {
            let conflicts: [MCPNotebookTools.RepeatConflict] = MCPNotebookTools.repeatConflicts(
                lessonID: lessonID, students: students, before: day, index: index
            )
            let intent = MCPNotebookTools.RepeatIntent(
                purpose: purpose, conflicts: conflicts, lessonID: lessonID, index: index
            )
            MCPNotebookTools.recordRepeatIntent(intent, draft: draft, plannedOn: day, in: context)
        }
        return draft
    }

    /// The same, for a caller holding ids rather than the children themselves.
    @discardableResult
    static func planDraft(
        lesson: CDLesson,
        studentIDs: Set<UUID>,
        purpose: RepeatPurpose?,
        plannedOn day: Date = Date(),
        in context: NSManagedObjectContext
    ) -> CDLessonAssignment? {
        guard !studentIDs.isEmpty else { return nil }
        let students = DataQueryService(context: context).fetchStudents(ids: studentIDs)
        return planDraft(
            lesson: lesson, students: students, purpose: purpose, plannedOn: day, in: context
        )
    }

    // MARK: - Plans Already Waiting

    /// A plan for the lesson: one already waiting, or a new draft.
    struct PlanResult {
        let plan: CDLessonAssignment
        /// False when the children were all on a waiting plan already, and
        /// `plan` is that plan, untouched.
        let isNew: Bool
    }

    /// The one "is it already planned?" check every planning path shares
    /// (bug hunt 2026-10-12, #32): a child already on a waiting plan for the
    /// lesson — a draft or a scheduled presentation not yet given — is left
    /// off the new draft, and when every child asked for is already planned,
    /// nothing is made and the waiting plan comes back (the one naming them
    /// all when there is one) for the caller to open. The class map's Plan
    /// and the Plan Presentation sheet's paths used to make a second draft.
    ///
    /// Nothing is saved.
    @discardableResult
    static func planOrReuse(
        lesson: CDLesson,
        students: [CDStudent],
        purpose: RepeatPurpose?,
        plannedOn day: Date = Date(),
        in context: NSManagedObjectContext
    ) -> PlanResult? {
        guard let lessonID = lesson.id else { return nil }
        let waiting = waitingPlans(lessonID: lessonID, in: context)
        let planned = Set(waiting.flatMap(\.resolvedStudentIDs))
        let unplanned = students.filter { $0.id.map { !planned.contains($0) } ?? false }
        if unplanned.isEmpty {
            let asked = Set(students.compactMap(\.id))
            guard !asked.isEmpty else { return nil }
            let covering = waiting.first { asked.isSubset(of: Set($0.resolvedStudentIDs)) }
                ?? waiting.first { !asked.isDisjoint(with: $0.resolvedStudentIDs) }
            return covering.map { PlanResult(plan: $0, isNew: false) }
        }
        return planDraft(lesson: lesson, students: unplanned, purpose: purpose, plannedOn: day, in: context)
            .map { PlanResult(plan: $0, isNew: true) }
    }

    /// The same, for a caller holding ids rather than the children themselves.
    @discardableResult
    static func planOrReuse(
        lesson: CDLesson,
        studentIDs: Set<UUID>,
        purpose: RepeatPurpose?,
        plannedOn day: Date = Date(),
        in context: NSManagedObjectContext
    ) -> PlanResult? {
        guard !studentIDs.isEmpty else { return nil }
        let students = DataQueryService(context: context).fetchStudents(ids: studentIDs)
        return planOrReuse(lesson: lesson, students: students, purpose: purpose, plannedOn: day, in: context)
    }

    /// What a planning path says when every child asked for is already on a
    /// waiting plan, so nothing new was made. The sheet used to close without
    /// a word, and a reason the guide chose went nowhere. The reason isn't put
    /// on the waiting plan (its notes are the guide's to write), so the message
    /// says it wasn't added rather than drop it quietly.
    static func alreadyPlannedMessage(purpose: RepeatPurpose?) -> String {
        guard let purpose else { return "Already planned for these children." }
        return "Already planned for these children, so nothing new was made and "
            + "“\(purpose.displayName.lowercased())” wasn’t added. Open their plan to add it."
    }

    /// The lesson's plans not yet given: drafts and scheduled presentations.
    static func waitingPlans(lessonID: UUID, in context: NSManagedObjectContext) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \CDLessonAssignment.createdAt, ascending: true)]
        return context.safeFetch(request).filter { !$0.isDeleted && !$0.isGiven }
    }

    // MARK: - Reading the Record for a Picker

    /// The children in `students` the record already covers for `lesson`,
    /// judged the way the regive guard judges them — a day on or after `day`
    /// is an edit of the record already there, not a repeat.
    static func repeatConflicts(
        lesson: CDLesson,
        students: [CDStudent],
        on day: Date = Date(),
        index: PresentationRecordIndex
    ) -> [MCPNotebookTools.RepeatConflict] {
        guard let lessonID = lesson.id?.uuidString else { return [] }
        return MCPNotebookTools.repeatConflicts(
            lessonID: lessonID, students: students, before: day, index: index
        )
    }
}
