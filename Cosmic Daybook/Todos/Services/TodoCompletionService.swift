// TodoCompletionService.swift
// Completing and reopening a todo, recurrence included.
//
// Completion used to live inline in Today's `toggleTodoItem` and again in
// the old to-do list panel, each spawning the next occurrence of a
// repeating todo its own way. This is the one place that rule lives now:
// Today's toggle, the Watching list's "Clear", and (since the 2026-10-10 bug
// hunt) the Todos screen's checkbox, its batch Complete and the editor's
// Completed switch all call it. Where the next occurrence lands is
// `TodoRepeatRule`.

import CoreData
import Foundation

@MainActor
enum TodoCompletionService {

    /// How far apart a next occurrence's `createdAt` and the `completedAt` of
    /// the todo whose completion made it can be: `complete` stamps both in
    /// one call, microseconds apart (milliseconds after a trip through
    /// iCloud).
    private static let sameCompletion: TimeInterval = 2

    /// Marks the todo done and, when it repeats, inserts its next occurrence
    /// into the same context. Does not save.
    static func complete(_ todo: CDTodoItem, calendar: Calendar = AppCalendar.shared) {
        todo.isCompleted = true
        todo.completedAt = Date()
        if todo.recurrence != .none {
            // `CDTodoItem(context:)` inserts the new row as it is created.
            _ = nextOccurrence(after: todo, calendar: calendar)
        }
    }

    /// Completes every open todo linked to `workID` (`linkedWorkItemID`), the
    /// way `complete` does, so a repeating one still gets its next occurrence.
    /// Called when the work is checked in or otherwise touched: the follow-up
    /// was about that work, and the work has now been seen. Does not save.
    @discardableResult
    static func completeTodosLinked(
        toWork workID: UUID, in context: NSManagedObjectContext, calendar: Calendar = AppCalendar.shared
    ) -> [CDTodoItem] {
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = NSPredicate(
            format: "isCompleted == NO AND linkedWorkItemID ==[c] %@", workID.uuidString
        )
        let linked = context.safeFetch(request)
        for todo in linked {
            complete(todo, calendar: calendar)
        }
        return linked
    }

    /// Reopens a completed todo. When completing it made the next occurrence
    /// of a repeat, that copy goes too, so tick, untick, tick leaves one next
    /// occurrence, not two (bug hunt 2026-10-10, P2 #22) — but only while the
    /// copy is still as `complete` made it: open, and with the same title,
    /// notes, children, tags, priority and dates, and no checklist. Does not
    /// save.
    static func reopen(_ todo: CDTodoItem) {
        if let copy = untouchedNextOccurrence(of: todo, calendar: AppCalendar.shared) {
            copy.managedObjectContext?.delete(copy)
        }
        todo.isCompleted = false
        todo.completedAt = nil
    }

    /// The next occurrence of a repeating todo, inserted into the todo's
    /// context, or nil when the pattern yields no next date. Its dates follow
    /// `TodoRepeatRule`, counted on the day the todo was completed.
    @discardableResult
    static func nextOccurrence(after todo: CDTodoItem, calendar: Calendar) -> CDTodoItem? {
        let completedOn = todo.completedAt ?? Date()
        guard let dates = repeatRule(for: todo).nextDates(today: completedOn, calendar: calendar),
              let context = todo.managedObjectContext else { return nil }

        let newTodo = CDTodoItem(context: context)
        newTodo.title = todo.title
        newTodo.notes = todo.notes
        newTodo.orderIndex = 0
        newTodo.studentIDs = todo.studentIDs
        newTodo.dueDate = dates.dueDate
        newTodo.scheduledDate = dates.scheduledDate
        newTodo.priority = todo.priority
        newTodo.recurrence = todo.recurrence
        newTodo.repeatAfterCompletion = todo.repeatAfterCompletion
        newTodo.customIntervalDays = todo.customIntervalDays
        newTodo.tags = todo.tags
        newTodo.linkedWorkItemID = todo.linkedWorkItemID
        return newTodo
    }

    /// `todo`'s repeat, with the date its own previous occurrence counted
    /// from when that one is still in the notebook (a month too short for
    /// the 31st gives it back to the month after).
    static func repeatRule(for todo: CDTodoItem) -> TodoRepeatRule {
        var rule = TodoRepeatRule(
            recurrence: todo.recurrence,
            customIntervalDays: todo.customIntervalDays,
            repeatAfterCompletion: todo.repeatAfterCompletion,
            dueDate: todo.dueDate,
            scheduledDate: todo.scheduledDate
        )
        if todo.recurrence == .monthly || todo.recurrence == .yearly, let previous = occurrence(before: todo) {
            rule.previousAnchorDate = previous.dueDate ?? previous.scheduledDate
        }
        return rule
    }

    /// The completed todo whose completion made `todo`, if it is still here.
    private static func occurrence(before todo: CDTodoItem) -> CDTodoItem? {
        guard let createdAt = todo.createdAt, let context = todo.managedObjectContext else { return nil }
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = sameSeries(as: todo, completed: true, dateKey: "completedAt", near: createdAt)
        return context.safeFetch(request).first { $0 !== todo }
    }

    /// The open next occurrence completing `todo` made, while nobody has
    /// changed it since.
    private static func untouchedNextOccurrence(of todo: CDTodoItem, calendar: Calendar) -> CDTodoItem? {
        guard todo.isCompleted, todo.recurrence != .none,
              let completedAt = todo.completedAt, let context = todo.managedObjectContext,
              let expected = repeatRule(for: todo).nextDates(today: completedAt, calendar: calendar)
        else { return nil }
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = sameSeries(as: todo, completed: false, dateKey: "createdAt", near: completedAt)
        return context.safeFetch(request).first { copy in
            copy !== todo
                && copy.notes == todo.notes
                && copy.priorityRaw == todo.priorityRaw
                && copy.repeatAfterCompletion == todo.repeatAfterCompletion
                && copy.customIntervalDays == todo.customIntervalDays
                && copy.studentIDsArray == todo.studentIDsArray
                && copy.tagsArray == todo.tagsArray
                && copy.linkedWorkItemID == todo.linkedWorkItemID
                && !copy.isSomeday
                && (copy.subtasks?.count ?? 0) == 0
                && isSameDate(copy.dueDate, expected.dueDate)
                && isSameDate(copy.scheduledDate, expected.scheduledDate)
        }
    }

    /// Todos of `todo`'s repeat, open or done, whose `dateKey` is within
    /// `sameCompletion` of `date`.
    private static func sameSeries(
        as todo: CDTodoItem, completed: Bool, dateKey: String, near date: Date
    ) -> NSPredicate {
        NSPredicate(
            format: "isCompleted == %@ AND title == %@ AND recurrenceRaw == %@ AND %K >= %@ AND %K <= %@",
            NSNumber(value: completed), todo.title, todo.recurrenceRaw,
            dateKey, date.addingTimeInterval(-sameCompletion) as NSDate,
            dateKey, date.addingTimeInterval(sameCompletion) as NSDate
        )
    }

    private static func isSameDate(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return abs(lhs.timeIntervalSince(rhs)) < 1
        default: return false
        }
    }
}
