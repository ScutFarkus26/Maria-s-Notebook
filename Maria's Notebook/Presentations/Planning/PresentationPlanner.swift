//
//  PresentationPlanner.swift
//  Maria's Notebook
//
//  Planning a lesson from a picker, with the reason when it is a regive.
//
//  Three surfaces now put a draft in the inbox from a lesson and a set of
//  children — the lessons list, the presentations overview and Today's ready
//  queue — and all three have to file a repeat the way the MCP tools do: a
//  second pass flags the child's previous record `needsAnotherPresentation`,
//  and either purpose opens the new draft's notes with the purpose line that
//  `student_presentation_history` reads back as "(2nd time; second pass)".
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
