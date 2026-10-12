//
//  MCPNotebookTools+FollowUps.swift
//  Cosmic Daybook
//
//  The guide's own follow-ups: adding one and marking it done. Split out of
//  +Meetings when the duplicate guard landed — the meeting file was already
//  at SwiftLint's file limit, and these two tools were never about meetings.
//
//  `add_follow_up` mirrors NewTodoForm.createTodo, student tag syncing
//  included, and refuses to file a second identical open todo the same day
//  unless the caller passes `force` (see +ObservationBatch for the guard).
//  `resolve_follow_up` completes a todo, resolves a goal, or clears an
//  observation's follow-up flag — the three rows of the app's Watching list
//  — the way that list's Clear does: a repeating todo is completed through
//  TodoCompletionService, which schedules its next occurrence.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Add Follow-Up

    static func addFollowUpTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "add_follow_up",
            title: "Add Follow-Up",
            description: "Add a follow-up to the guide's todo list — something owed to a "
                + "student, a parent, an assistant, or the guide themself. Optionally tied to "
                + "students, dated, prioritized, or filed under someday. When it is about one "
                + "specific piece of work (\"check in with Maya on her map\"), pass that work's "
                + "work_id so it shows on the work's row. For a goal a student owns, use the "
                + "goals field of create_meeting_entry instead. An identical open follow-up "
                + "from today is reported rather than duplicated, unless force is true.",
            inputSchema: addFollowUpSchema,
            annotations: .write,
            handler: { arguments in
                try undoingOnFailure(context()) { try addFollowUp(arguments: arguments, in: $0) }
            }
        )
    }

    private static let addFollowUpSchema: JSONValue = [
        "type": "object",
        "properties": [
            "title": [
                "type": "string",
                "description": "What is owed, phrased as an action"
            ],
            "notes": [
                "type": "string",
                "description": "Optional detail behind the follow-up"
            ],
            "student_names": [
                "type": "array",
                "items": ["type": "string"],
                "description": "Students this follow-up concerns, if any: names, or ids from list_students"
            ],
            "due_date": [
                "type": "string",
                "description": "Due date as YYYY-MM-DD, if there is a deadline"
            ],
            "scheduled_date": [
                "type": "string",
                "description": "The day the guide means to do it, YYYY-MM-DD"
            ],
            "priority": todoPrioritySchema,
            "work_id": todoWorkIDSchema,
            "is_someday": [
                "type": "boolean",
                "description": .string("File it under someday/maybe rather than the "
                    + "active list (default false); refused beside scheduled_date")
            ],
            "force": [
                "type": "boolean",
                "description": .string("Add it even though an identical open follow-up "
                    + "already exists from today (default false)")
            ]
        ],
        "required": ["title"]
    ]

    static func addFollowUp(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let title = try requireString(arguments, "title")
        let names = stringArrayArgument(arguments, "student_names")
        // A name or an id, as create_observation takes (two Ettys), and one
        // child named twice is one child.
        let students = try names.map { try resolveStudentReference($0, in: modelContext) }.uniqueByID
        let studentIDs = students.compactMap(\.id)
        guard studentIDs.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }
        let workLink = try todoWorkLinkChange(arguments, allowClear: false, in: modelContext)
        let dueDate = try dayArgument(arguments, "due_date")
        let scheduledDate = try dayArgument(arguments, "scheduled_date")
        let priority = try todoPriorityArgument(arguments)
        let isSomeday = arguments["is_someday"]?.boolValue ?? false
        // As update_todo refuses it: Today and the lists hide someday todos,
        // so a day on one never showed.
        if scheduledDate != nil, isSomeday {
            throw MCPToolError(
                "Pass scheduled_date or is_someday: true, not both — a follow-up with a day is not "
                    + "someday. Nothing was added."
            )
        }
        if let notice = duplicateFollowUpNotice(
            title: title, studentIDs: studentIDs,
            force: arguments["force"]?.boolValue ?? false, in: modelContext
        ) {
            return notice
        }

        let todo = CDTodoItem(context: modelContext)
        todo.title = title
        todo.notes = arguments["notes"]?.stringValue?.trimmed() ?? ""
        todo.studentIDsArray = studentIDs.map(\.uuidString)
        todo.dueDate = dueDate
        todo.scheduledDate = scheduledDate
        if let priority {
            todo.priority = priority
        }
        todo.isSomeday = isSomeday
        todo.tagsArray = TodoTagHelper.syncStudentTags(
            existingTags: [], studentNames: students.map(\.fullName)
        )
        let linkPhrase = applyTodoWorkLink(workLink, to: todo)

        guard modelContext.safeSave() else {
            throw MCPToolError("The follow-up could not be saved.")
        }

        let details = followUpDetails(
            dueDate: dueDate, scheduledDate: scheduledDate, isSomeday: isSomeday,
            priority: priority, students: students
        ) + [linkPhrase].compactMap { $0 }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"
        return "Added follow-up [todo id=\(citationID(todo.id))] \"\(title)\"\(suffix)."
    }

    /// The parenthetical on the receipt: everything the caller set beyond the
    /// title, in the order the in-app list shows it.
    private static func followUpDetails(
        dueDate: Date?, scheduledDate: Date?, isSomeday: Bool,
        priority: TodoPriority?, students: [CDStudent]
    ) -> [String] {
        var details: [String] = []
        if let dueDate {
            details.append("due \(dayString(dueDate))")
        }
        if let scheduledDate {
            details.append("scheduled \(dayString(scheduledDate))")
        }
        if isSomeday {
            details.append("someday")
        }
        if let priority, priority != .none {
            details.append("\(priority.rawValue.lowercased()) priority")
        }
        if !students.isEmpty {
            details.append(students.map(\.fullName).joined(separator: ", "))
        }
        return details
    }

    // MARK: - Resolve Follow-Up

    static func resolveFollowUpTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "resolve_follow_up",
            title: "Resolve Follow-Up",
            description: "Mark a follow-up done: completes a todo, resolves a student's "
                + "open goal (focus item), or clears an observation's follow-up flag, by the "
                + "id shown in list_open_follow_ups. A repeating todo is completed and its next "
                + "occurrence scheduled, as the app does.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": [
                        "type": "string",
                        "description": "The todo, focus item or note UUID from list_open_follow_ups"
                    ]
                ],
                "required": ["id"]
            ],
            annotations: .idempotentWrite,
            handler: { arguments in
                try undoingOnFailure(context()) { try resolveFollowUp(arguments: arguments, in: $0) }
            }
        )
    }

    static func resolveFollowUp(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let idString = try requireString(arguments, "id")
        guard let id = UUID(uuidString: idString) else {
            throw MCPToolError("id must be a UUID from list_open_follow_ups.")
        }

        if let todo = modelContext.object(CDTodoItem.self, id: id) {
            return try completeTodo(todo, idString: idString, in: modelContext)
        }

        if let item = modelContext.object(CDStudentFocusItem.self, id: id) {
            return try resolveGoal(item, idString: idString, in: modelContext)
        }

        if let note = modelContext.object(CDNote.self, id: id) {
            return try clearFlag(on: note, idString: idString, in: modelContext)
        }

        throw MCPToolError("No follow-up, goal or flagged note with id \(idString) was found.")
    }

    /// Completed the way the Watching list's Clear and Today's checkbox do,
    /// so a repeating todo gets its next occurrence. The receipt names it.
    private static func completeTodo(
        _ todo: CDTodoItem, idString: String, in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard !todo.isCompleted else {
            MCPCallOutcome.markNothingWritten()
            return "Follow-up [todo id=\(idString)] \"\(todo.title)\" is already completed."
        }
        TodoCompletionService.complete(todo)
        let next = modelContext.insertedObjects
            .compactMap { $0 as? CDTodoItem }
            .first { $0 !== todo && $0.title == todo.title && $0.recurrence == todo.recurrence }
        guard modelContext.safeSave() else {
            throw MCPToolError("The follow-up could not be saved.")
        }
        var receipt = "Completed follow-up [todo id=\(idString)] \"\(todo.title)\"."
        if let next {
            let when = (next.scheduledDate ?? next.dueDate).map { " for \(dayString($0))" } ?? ""
            receipt += " It repeats, so the next one is on the list\(when) [todo id=\(citationID(next.id))]."
        }
        return receipt
    }

    /// Resolved outside a meeting, so no resolving meeting is recorded.
    private static func resolveGoal(
        _ item: CDStudentFocusItem, idString: String, in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard item.isActive else {
            MCPCallOutcome.markNothingWritten()
            return "Goal [focusItem id=\(idString)] \"\(item.text)\" is already "
                + "\(item.status.rawValue)."
        }
        FocusItemService.resolve(item)
        guard modelContext.safeSave() else {
            throw MCPToolError("The goal could not be saved.")
        }
        return "Resolved goal [focusItem id=\(idString)] \"\(item.text)\"."
    }

    /// The same path the note editor's flag toggle takes, so `updatedAt` moves.
    private static func clearFlag(
        on note: CDNote, idString: String, in modelContext: NSManagedObjectContext
    ) throws -> String {
        guard note.needsFollowUp, let id = note.id else {
            MCPCallOutcome.markNothingWritten()
            return "The follow-up flag on [note id=\(idString)] is already cleared."
        }
        NoteRepository(context: modelContext).updateNote(id: id, needsFollowUp: false)
        guard modelContext.safeSave() else {
            throw MCPToolError("The note could not be saved.")
        }
        announceSavedNote(id)
        return "Cleared the follow-up flag on [note id=\(idString)]."
    }
}
