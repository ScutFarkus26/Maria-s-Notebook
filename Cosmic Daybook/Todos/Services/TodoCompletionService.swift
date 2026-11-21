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
import CryptoKit
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
    /// notes, children, tags, priority and dates, no checklist, and not yet
    /// shared with Tide. The copy is found by its id (`nextOccurrenceID`),
    /// else by title for one made before ids were worked out; a copy whose
    /// title now differs stays, as nobody can tell whether it or the todo
    /// was renamed, and completing the todo again makes no second one.
    /// Does not save.
    static func reopen(_ todo: CDTodoItem) {
        if let copy = untouchedNextOccurrence(of: todo, calendar: AppCalendar.shared) {
            copy.managedObjectContext?.delete(copy)
        }
        todo.isCompleted = false
        todo.completedAt = nil
    }

    /// The next occurrence of a repeating todo, inserted into the todo's
    /// context, or nil when the pattern yields no next date. Its dates follow
    /// `TodoRepeatRule`, counted on the day the todo was completed; its id
    /// is `nextOccurrenceID` of the todo's, so two devices completing the
    /// same todo make one next occurrence once they sync (plan "Domain logic
    /// fixes", R25). When that next occurrence is already here (an untick
    /// kept it because it had been changed), it is returned and none is made.
    @discardableResult
    static func nextOccurrence(after todo: CDTodoItem, calendar: Calendar) -> CDTodoItem? {
        let completedOn = todo.completedAt ?? Date()
        guard let dates = repeatRule(for: todo).nextDates(today: completedOn, calendar: calendar),
              let context = todo.managedObjectContext else { return nil }

        // Completing it again (after an untick that kept a changed copy)
        // makes no second copy: the one with the id stands.
        var nextID: UUID?
        if let id = todo.id {
            let next = nextOccurrenceID(of: id)
            let request = CDFetchRequest(CDTodoItem.self)
            request.predicate = NSPredicate(format: "id == %@", next as CVarArg)
            if let existing = context.safeFetch(request).first(where: { !$0.isDeleted && $0 !== todo }) {
                return existing
            }
            nextID = next
        }
        let newTodo = CDTodoItem(context: context)
        if let nextID { newTodo.id = nextID }
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

    /// The id of the next occurrence that completing the to-do `id` makes:
    /// the first 16 bytes of a SHA-256 of it, marked as an RFC 9562 version 8
    /// (custom) UUID, as `TimetableService.splitCopyID` does for blocks. Two
    /// devices completing the same to-do before they sync make the same next
    /// occurrence, and the same-id cleanup folds the two into one.
    nonisolated static func nextOccurrenceID(of id: UUID) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("TodoNextOccurrence|\(id.uuidString)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
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

    /// The completed todo whose completion made `todo`, if it is still here:
    /// the one whose `nextOccurrenceID` is `todo`'s id, so a rename doesn't
    /// lose it, else (a next occurrence made before ids were worked out) one
    /// with the same title.
    private static func occurrence(before todo: CDTodoItem) -> CDTodoItem? {
        guard let createdAt = todo.createdAt, let context = todo.managedObjectContext else { return nil }
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = sameSeries(
            as: todo, completed: true, dateKey: "completedAt", near: createdAt, byTitle: false
        )
        let near = context.safeFetch(request).filter { $0 !== todo }
        if let id = todo.id, let made = near.first(where: { $0.id.map(nextOccurrenceID(of:)) == id }) {
            return made
        }
        return near.first { $0.title == todo.title }
    }

    /// The open next occurrence completing `todo` made, while nobody has
    /// changed it since: found by its id (`nextOccurrenceID`), so a rename of
    /// either doesn't lose it, else (one made before ids were worked out) by
    /// the title and when it was made.
    private static func untouchedNextOccurrence(of todo: CDTodoItem, calendar: Calendar) -> CDTodoItem? {
        guard todo.isCompleted, todo.recurrence != .none,
              let completedAt = todo.completedAt, let context = todo.managedObjectContext,
              let expected = repeatRule(for: todo).nextDates(today: completedAt, calendar: calendar)
        else { return nil }
        let request = CDFetchRequest(CDTodoItem.self)
        var candidates: [CDTodoItem] = []
        if let id = todo.id {
            request.predicate = NSPredicate(
                format: "isCompleted == NO AND id == %@", nextOccurrenceID(of: id) as CVarArg
            )
            candidates = context.safeFetch(request).filter { $0 !== todo }
        }
        if candidates.isEmpty {
            request.predicate = sameSeries(as: todo, completed: false, dateKey: "createdAt", near: completedAt)
            candidates = context.safeFetch(request)
        }
        return candidates.first { copy in
            copy !== todo
                && copy.title == todo.title
                && copy.notes == todo.notes
                && copy.priorityRaw == todo.priorityRaw
                && copy.repeatAfterCompletion == todo.repeatAfterCompletion
                && copy.customIntervalDays == todo.customIntervalDays
                && copy.studentIDsArray == todo.studentIDsArray
                && copy.tagsArray == todo.tagsArray
                && copy.linkedWorkItemID == todo.linkedWorkItemID
                && !copy.isSomeday
                // Once sent to Tide it isn't untouched: deleting it would
                // leave its Tide action with no copy here.
                && copy.tideLink == nil
                // A copy with checklist rows (TodoSubtask, retired 2026-11-03,
                // rows kept) isn't untouched either.
                && ((copy.value(forKey: "subtasks") as? NSSet)?.count ?? 0) == 0
                && isSameDate(copy.dueDate, expected.dueDate)
                && isSameDate(copy.scheduledDate, expected.scheduledDate)
        }
    }

    /// Todos of `todo`'s repeat, open or done, whose `dateKey` is within
    /// `sameCompletion` of `date`: with `todo`'s title, unless `byTitle` is false.
    private static func sameSeries(
        as todo: CDTodoItem, completed: Bool, dateKey: String, near date: Date, byTitle: Bool = true
    ) -> NSPredicate {
        let series = NSPredicate(
            format: "isCompleted == %@ AND recurrenceRaw == %@ AND %K >= %@ AND %K <= %@",
            NSNumber(value: completed), todo.recurrenceRaw,
            dateKey, date.addingTimeInterval(-sameCompletion) as NSDate,
            dateKey, date.addingTimeInterval(sameCompletion) as NSDate
        )
        guard byTitle else { return series }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            series, NSPredicate(format: "title == %@", todo.title)
        ])
    }

    private static func isSameDate(_ lhs: Date?, _ rhs: Date?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?): return abs(lhs.timeIntervalSince(rhs)) < 1
        default: return false
        }
    }
}
