//
//  MCPNotebookTools+FollowUps.swift
//  Maria's Notebook
//
//  The guide's own follow-ups: adding one and marking it done. Split out of
//  +Meetings when the duplicate guard landed — the meeting file was already
//  at SwiftLint's file limit, and these two tools were never about meetings.
//
//  `add_follow_up` mirrors NewTodoForm.createTodo, student tag syncing
//  included, and refuses to file a second identical open todo the same day
//  unless the caller passes `force` (see +ObservationBatch for the guard).
//  `resolve_follow_up` completes a todo or resolves a goal, and refuses
//  recurring todos because only the app schedules the next occurrence.
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
                + "students, dated, prioritised, or filed under someday. For a goal a student "
                + "owns, use the goals field of create_meeting_entry instead. An identical "
                + "open follow-up from today is reported rather than duplicated, unless "
                + "force is true.",
            inputSchema: addFollowUpSchema,
            handler: { arguments in
                try addFollowUp(arguments: arguments, in: context())
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
                "description": "Students this follow-up concerns, if any"
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
            "is_someday": [
                "type": "boolean",
                "description": .string("File it under someday/maybe rather than the "
                    + "active list (default false)")
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
        let students = try names.map { try resolveStudent(named: $0, in: modelContext) }
        let studentIDs = students.compactMap(\.id)
        guard studentIDs.count == students.count else {
            throw MCPToolError("A matched student record has no identifier.")
        }
        if let notice = duplicateFollowUpNotice(
            title: title, studentIDs: studentIDs,
            force: arguments["force"]?.boolValue ?? false, in: modelContext
        ) {
            return notice
        }
        let dueDate = try dayArgument(arguments, "due_date")
        let scheduledDate = try dayArgument(arguments, "scheduled_date")
        let priority = try todoPriorityArgument(arguments)
        let isSomeday = arguments["is_someday"]?.boolValue ?? false

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

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The follow-up could not be saved.")
        }

        let details = followUpDetails(
            dueDate: dueDate, scheduledDate: scheduledDate, isSomeday: isSomeday,
            priority: priority, students: students
        )
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
            description: "Mark a follow-up done: completes a todo, or resolves a student's "
                + "open goal (focus item), by the id shown in list_open_follow_ups.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": [
                        "type": "string",
                        "description": "The todo or focus item UUID from list_open_follow_ups"
                    ]
                ],
                "required": ["id"]
            ],
            handler: { arguments in
                try resolveFollowUp(arguments: arguments, in: context())
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
            guard !todo.isCompleted else {
                return "Follow-up [todo id=\(idString)] \"\(todo.title)\" is already completed."
            }
            guard todo.recurrence == .none else {
                throw MCPToolError(
                    "\"\(todo.title)\" is a repeating todo; complete it in the app so the next "
                        + "occurrence is scheduled."
                )
            }
            todo.isCompleted = true
            todo.completedAt = Date()
            guard modelContext.safeSave() else {
                modelContext.rollback()
                throw MCPToolError("The follow-up could not be saved.")
            }
            return "Completed follow-up [todo id=\(idString)] \"\(todo.title)\"."
        }

        if let item = modelContext.object(CDStudentFocusItem.self, id: id) {
            guard item.isActive else {
                return "Goal [focusItem id=\(idString)] \"\(item.text)\" is already "
                    + "\(item.status.rawValue)."
            }
            // Resolved outside a meeting, so no resolving meeting is recorded.
            item.status = .resolved
            item.resolvedAt = Date()
            guard modelContext.safeSave() else {
                modelContext.rollback()
                throw MCPToolError("The goal could not be saved.")
            }
            return "Resolved goal [focusItem id=\(idString)] \"\(item.text)\"."
        }

        throw MCPToolError("No follow-up or goal with id \(idString) was found.")
    }
}
