//
//  MCPNotebookTools+TodoWhen.swift
//  Cosmic Daybook
//
//  update_todo's dates: the deadline, and the When day and Someday, which
//  exclude each other as in the app's When popover. Split out of +Todos
//  when reporting only the When changes that happened took that file past
//  SwiftLint's length limit.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// Where a todo stands in the When popover's terms, for a reply.
    static func whenState(of todo: CDTodoItem) -> String {
        if todo.isSomeday { return "in someday" }
        if let day = todo.scheduledDate { return "scheduled \(dayString(day))" }
        return "out of someday, with no day"
    }

    static func applyTodoDates(
        _ arguments: [String: JSONValue], to todo: CDTodoItem
    ) throws -> [String] {
        var changes: [String] = []
        if arguments["clear_due_date"]?.boolValue == true {
            todo.dueDate = nil
            changes.append("cleared the due date")
        } else if let due = try dayArgument(arguments, "due_date") {
            todo.dueDate = due
            changes.append("due \(dayString(due))")
        }
        changes += try applyTodoWhen(arguments, to: todo)
        return changes
    }

    /// The When day and Someday exclude each other, as in the app's When
    /// popover (`TodoScheduling`): a day takes the todo out of Someday, and
    /// Someday clears the day. The deadline is left alone either way. Today
    /// and the lists hide Someday todos, so a day set on one that stayed in
    /// Someday never showed (bug hunt 2026-10-12, #23).
    private static func applyTodoWhen(
        _ arguments: [String: JSONValue], to todo: CDTodoItem
    ) throws -> [String] {
        let scheduled: Date? = try dayArgument(arguments, "scheduled_date")
        let someday: Bool? = arguments["is_someday"]?.boolValue
        if scheduled != nil, someday == true {
            throw MCPToolError(
                "Pass scheduled_date or is_someday: true, not both — a todo with a day is not someday."
            )
        }
        // A line only for what actually changed: a todo already on that day,
        // already in someday, or already out of it reported (and journaled) a
        // change that wasn't one.
        var changes: [String] = []
        if let scheduled {
            let leftSomeday: Bool = todo.isSomeday
            let sameDay: Bool = todo.scheduledDate.map { AppCalendar.isSameDay($0, scheduled) } ?? false
            guard leftSomeday || !sameDay else { return [] }
            todo.scheduledDate = scheduled
            todo.isSomeday = false
            changes.append("scheduled \(dayString(scheduled))" + (leftSomeday ? " (out of someday)" : ""))
        } else if someday == true {
            let hadDay: Date? = todo.scheduledDate
            guard !todo.isSomeday || hadDay != nil else { return [] }
            todo.scheduledDate = nil
            todo.isSomeday = true
            changes.append("moved to someday" + (hadDay.map { " (cleared the day \(dayString($0)))" } ?? ""))
        } else if someday == false {
            guard todo.isSomeday else { return [] }
            todo.isSomeday = false
            changes.append("moved out of someday")
        }
        return changes
    }
}
