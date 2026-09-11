//
//  MCPNotebookTools+Todos.swift
//  Maria's Notebook
//
//  The guide's own list. `list_open_follow_ups` answers "what is owed right
//  now" across todos, goals and flagged notes; these two tools are the todo
//  list itself — filterable, and editable field by field.
//
//  Completion stays with `resolve_follow_up`, which refuses recurring todos
//  because only the app schedules the next occurrence.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Listing

    static func listTodosTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_todos",
            title: "List Todos",
            description: "The guide's todo list, filtered: open or completed, due within a "
                + "window, someday items, tagged, or concerning one student. For the broader "
                + "\"what is owed right now\" across goals and flagged notes, use "
                + "list_open_follow_ups instead.",
            inputSchema: listTodosSchema,
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let filter = try TodoFilter(arguments: arguments, in: modelContext)
                return describeTodos(filter, in: modelContext)
            }
        )
    }

    private static let listTodosSchema: JSONValue = [
        "type": "object",
        "properties": [
            "status": [
                "type": "string",
                "enum": ["open", "completed", "all"],
                "description": "Which todos to list (default open)"
            ],
            "student_name": [
                "type": "string",
                "description": "Only todos concerning this student"
            ],
            "due_before": [
                "type": "string",
                "description": "Only todos due on or before this day, YYYY-MM-DD"
            ],
            "due_after": [
                "type": "string",
                "description": "Only todos due on or after this day, YYYY-MM-DD"
            ],
            "include_someday": [
                "type": "boolean",
                "description": "Include someday/maybe items (default true)"
            ],
            "tag": [
                "type": "string",
                "description": "Only todos carrying this tag"
            ],
            "limit": [
                "type": "integer",
                "description": "Maximum todos to return, 1-100 (default 40)"
            ]
        ]
    ]

    /// The parsed shape of a `list_todos` request. Built up front so a bad
    /// argument fails before any fetching happens.
    private struct TodoFilter {
        let status: String
        let studentID: UUID?
        let studentName: String?
        let dueBefore: Date?
        let dueAfter: Date?
        let includeSomeday: Bool
        let tag: String?
        let limit: Int

        init(arguments: [String: JSONValue], in modelContext: NSManagedObjectContext) throws {
            let requested = nonEmpty(arguments["status"]?.stringValue) ?? "open"
            guard ["open", "completed", "all"].contains(requested) else {
                throw MCPToolError("status must be open, completed or all. Got \"\(requested)\".")
            }
            status = requested

            if let name = nonEmpty(arguments["student_name"]?.stringValue) {
                let student = try resolveStudentReference(name, in: modelContext)
                guard let id = student.id else {
                    throw MCPToolError("That student record has no identifier.")
                }
                studentID = id
                studentName = student.fullName
            } else {
                studentID = nil
                studentName = nil
            }

            dueBefore = try dayArgument(arguments, "due_before")
            dueAfter = try dayArgument(arguments, "due_after")
            includeSomeday = arguments["include_someday"]?.boolValue ?? true
            tag = nonEmpty(arguments["tag"]?.stringValue)
            limit = intArgument(arguments, "limit", default: 40, range: 1...100)
        }

        func matches(_ todo: CDTodoItem) -> Bool {
            let done: Bool = todo.isCompleted
            if status == "open" && done { return false }
            if status == "completed" && !done { return false }
            if !includeSomeday && todo.isSomeday { return false }
            if let studentID, !todo.studentIDsArray.contains(studentID.uuidString) { return false }
            if let tag, !hasTag(todo, tag) { return false }
            return matchesDueWindow(todo)
        }

        /// A date window asks about scheduled work, so an undated todo is not an
        /// answer to it — excluded rather than sorted to the end.
        private func matchesDueWindow(_ todo: CDTodoItem) -> Bool {
            if dueBefore == nil && dueAfter == nil { return true }
            guard let rawDue = todo.dueDate else { return false }
            let due: Date = AppCalendar.startOfDay(rawDue)
            if let dueBefore, due > AppCalendar.startOfDay(dueBefore) { return false }
            if let dueAfter, due < AppCalendar.startOfDay(dueAfter) { return false }
            return true
        }

        private func hasTag(_ todo: CDTodoItem, _ tag: String) -> Bool {
            for candidate in todo.tagsArray where candidate.caseInsensitiveCompare(tag) == .orderedSame {
                return true
            }
            return false
        }
    }

    private static func describeTodos(
        _ filter: TodoFilter, in modelContext: NSManagedObjectContext
    ) -> String {
        let all = modelContext.safeFetch(CDFetchRequest(CDTodoItem.self))
        let matched = all.filter { filter.matches($0) }
        let sorted = matched.sorted { lhs, rhs in
            let leftDue = lhs.dueDate ?? Date.distantFuture
            let rightDue = rhs.dueDate ?? Date.distantFuture
            if leftDue != rightDue { return leftDue < rightDue }
            return (lhs.createdAt ?? .distantPast) < (rhs.createdAt ?? .distantPast)
        }
        let shown = Array(sorted.prefix(filter.limit))

        guard !shown.isEmpty else {
            let who = filter.studentName.map { " for \($0)" } ?? ""
            return "No \(filter.status == "all" ? "" : filter.status + " ")todos\(who) match that."
        }

        let names = studentNameIndex(in: modelContext)
        let lines = shown.map { todoLine($0, names: names) }
        let more = sorted.count > shown.count
            ? "\n(\(sorted.count - shown.count) more not shown — raise limit or narrow the filter.)"
            : ""
        return "\(sorted.count) todo(s):\n" + lines.joined(separator: "\n") + more
    }

    private static func todoLine(_ todo: CDTodoItem, names: [String: String]) -> String {
        var details: [String] = []
        if todo.isCompleted {
            details.append("done \(dayString(todo.completedAt))")
        }
        if let due = todo.dueDate {
            details.append("due \(dayString(due))")
        }
        if let scheduled = todo.scheduledDate {
            details.append("scheduled \(dayString(scheduled))")
        }
        if todo.isSomeday {
            details.append("someday")
        }
        if todo.priority != .none {
            details.append(todo.priority.rawValue.lowercased() + " priority")
        }
        if todo.recurrence != .none {
            details.append("repeats")
        }
        let who = todo.studentIDsArray.compactMap { names[$0] }
        if !who.isEmpty {
            details.append(who.joined(separator: ", "))
        }
        let subtasks = subtaskProgress(of: todo)
        if subtasks.total > 0 {
            details.append("\(subtasks.done)/\(subtasks.total) subtasks")
        }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"
        let id = todo.id?.uuidString ?? "unknown"
        return "- [todo id=\(id)] \(todo.title)\(suffix)"
    }

    private static func subtaskProgress(of todo: CDTodoItem) -> (done: Int, total: Int) {
        let subtasks = (todo.subtasks?.allObjects as? [CDTodoSubtask]) ?? []
        return (subtasks.filter(\.isCompleted).count, subtasks.count)
    }

    /// Student full names keyed by uuid string, for resolving the string
    /// foreign keys todos carry.
    static func studentNameIndex(in modelContext: NSManagedObjectContext) -> [String: String] {
        let students = modelContext.safeFetch(CDFetchRequest(CDStudent.self))
        return Dictionary(
            students.compactMap { student in student.id.map { ($0.uuidString, student.fullName) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    // MARK: - Updating

    static func updateTodoTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "update_todo",
            title: "Update Todo",
            description: "Edit a todo by its id: title, notes, due or scheduled date, priority, "
                + "someday flag, or which students it concerns. Only the fields provided are "
                + "changed. To mark one done, use resolve_follow_up.",
            inputSchema: updateTodoSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                try updateTodo(arguments: arguments, in: context())
            }
        )
    }

    private static let updateTodoSchema: JSONValue = [
        "type": "object",
        "properties": [
            "todo_id": [
                "type": "string",
                "description": "The todo's id, as returned by list_todos or list_open_follow_ups"
            ],
            "title": ["type": "string", "description": "New title"],
            "notes": ["type": "string", "description": "New notes (replaces what is there)"],
            "due_date": ["type": "string", "description": "New due date, YYYY-MM-DD"],
            "clear_due_date": ["type": "boolean", "description": "Remove the due date"],
            "scheduled_date": [
                "type": "string",
                "description": "The day the guide means to do it, YYYY-MM-DD"
            ],
            "priority": todoPrioritySchema,
            "is_someday": [
                "type": "boolean",
                "description": "Move to (or out of) someday/maybe"
            ],
            "student_names": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Replace the students this todo concerns"
            ]
        ],
        "required": ["todo_id"]
    ]

    private static func updateTodo(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let todo = try resolveTodo(requireString(arguments, "todo_id"), in: modelContext)
        var changes: [String] = []

        if let title = nonEmpty(arguments["title"]?.stringValue) {
            todo.title = title
            changes.append("title")
        }
        if let notes = arguments["notes"]?.stringValue {
            todo.notes = notes.trimmed()
            changes.append("notes")
        }
        changes += try applyTodoDates(arguments, to: todo)
        if let priority = try todoPriorityArgument(arguments) {
            todo.priority = priority
            changes.append("priority \(priority.rawValue.lowercased())")
        }
        if let someday = arguments["is_someday"]?.boolValue {
            todo.isSomeday = someday
            changes.append(someday ? "moved to someday" : "moved out of someday")
        }
        changes += try applyTodoStudents(arguments, to: todo, in: modelContext)

        guard !changes.isEmpty else {
            throw MCPToolError("Nothing to change — pass at least one field to update.")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The todo could not be updated.")
        }
        let id = todo.id?.uuidString ?? "unknown"
        return "[todo id=\(id)] \(todo.title): updated \(changes.joined(separator: ", "))."
    }

    private static func applyTodoDates(
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
        if let scheduled = try dayArgument(arguments, "scheduled_date") {
            todo.scheduledDate = scheduled
            changes.append("scheduled \(dayString(scheduled))")
        }
        return changes
    }

    /// Replacing the student list also rewrites the student tags, the way the
    /// in-app form does — otherwise the todo keeps tags for children it no
    /// longer concerns.
    private static func applyTodoStudents(
        _ arguments: [String: JSONValue], to todo: CDTodoItem,
        in modelContext: NSManagedObjectContext
    ) throws -> [String] {
        guard let entries = arguments["student_names"]?.arrayValue else { return [] }
        let names = entries.compactMap { $0.stringValue?.trimmed() }.filter { !$0.isEmpty }
        let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
        let ids = students.compactMap(\.id)
        guard ids.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }
        todo.studentIDsArray = ids.map(\.uuidString)
        todo.tagsArray = TodoTagHelper.syncStudentTags(
            existingTags: todo.tagsArray, studentNames: students.map(\.fullName)
        )
        return students.isEmpty
            ? ["cleared the students"]
            : ["students \(students.map(\.fullName).joined(separator: ", "))"]
    }

    /// The priority field as both `update_todo` and `add_follow_up` declare it.
    static let todoPrioritySchema: JSONValue = [
        "type": "string",
        "enum": ["None", "Low", "Medium", "High"],
        "description": "Priority level"
    ]

    /// Parses an optional priority argument, shared so both todo writers name
    /// the same allowed values in the same error.
    static func todoPriorityArgument(
        _ arguments: [String: JSONValue], _ key: String = "priority"
    ) throws -> TodoPriority? {
        guard let raw = nonEmpty(arguments[key]?.stringValue) else { return nil }
        guard let priority = TodoPriority(rawValue: raw) else {
            let allowed = TodoPriority.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("\(key) must be one of: \(allowed). Got \"\(raw)\".")
        }
        return priority
    }

    static func resolveTodo(
        _ reference: String, in modelContext: NSManagedObjectContext
    ) throws -> CDTodoItem {
        guard let id = UUID(uuidString: reference) else {
            throw MCPToolError("todo_id must be a uuid, got \"\(reference)\".")
        }
        let request = CDFetchRequest(CDTodoItem.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let todo = modelContext.safeFetch(request).first else {
            throw MCPToolError("No todo with id \(reference) was found.")
        }
        return todo
    }
}
