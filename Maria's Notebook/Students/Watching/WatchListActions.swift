// WatchListActions.swift
// Clearing a WatchList row and opening the record behind it.
//
// A row is derived, so "clear" means acting on its source: unflag the note,
// complete the todo, resolve the goal. Each goes through the same path the
// source's own screen uses, so nothing here invents a second way to finish a
// record.

import CoreData
import Foundation

/// The record a row opens onto.
@MainActor
enum WatchSource {
    case note(CDNote)
    case todo(CDTodoItem)
    /// The meeting the goal was set in, when it still exists; otherwise the
    /// child's own page is the best place to land.
    case meeting(CDStudentMeeting?, studentID: UUID)
}

@MainActor
enum WatchListActions {

    /// Unflags the note, completes the todo, or resolves the goal — then
    /// saves. Returns false when the source is gone or the save failed.
    ///
    /// A flagged note names every child it is about; clearing one child's row
    /// clears the note's flag for all of them.
    @discardableResult
    static func clear(
        _ item: WatchItem,
        in context: NSManagedObjectContext,
        calendar: Calendar = AppCalendar.shared
    ) -> Bool {
        switch item.kind {
        case .flaggedNote:
            let repository = NoteRepository(context: context)
            guard repository.updateNote(id: item.sourceID, needsFollowUp: false) else { return false }
            guard context.safeSave() else { return false }
            // Today's recent-notes list and the observation timelines listen.
            NotificationCenter.default.post(name: .noteDidSave, object: item.sourceID)
            return true

        case .watchTodo:
            guard let todo = context.object(CDTodoItem.self, id: item.sourceID) else { return false }
            guard !todo.isCompleted else { return true }
            TodoCompletionService.complete(todo, calendar: calendar)
            return context.safeSave()

        case .goal:
            guard let goal = context.object(CDStudentFocusItem.self, id: item.sourceID) else { return false }
            guard goal.isActive else { return true }
            FocusItemService.resolve(goal)
            return context.safeSave()
        }
    }

    /// The record behind a row, or nil when it has since been deleted.
    static func open(_ item: WatchItem, in context: NSManagedObjectContext) -> WatchSource? {
        switch item.kind {
        case .flaggedNote:
            return context.object(CDNote.self, id: item.sourceID).map(WatchSource.note)
        case .watchTodo:
            return context.object(CDTodoItem.self, id: item.sourceID).map(WatchSource.todo)
        case .goal:
            guard let goal = context.object(CDStudentFocusItem.self, id: item.sourceID),
                  let studentID = goal.studentIDUUID ?? item.studentID else { return nil }
            let meeting = goal.createdInMeetingIDUUID.flatMap {
                context.object(CDStudentMeeting.self, id: $0)
            }
            return .meeting(meeting, studentID: studentID)
        }
    }
}
