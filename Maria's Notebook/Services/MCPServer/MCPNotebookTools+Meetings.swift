//
//  MCPNotebookTools+Meetings.swift
//  Maria's Notebook
//
//  Meeting and follow-up tools. Meeting entries follow the same save path
//  as the in-app meeting form (MeetingFormPane.saveAndContinue): build the
//  CDStudentMeeting, create focus items through FocusItemService, snapshot
//  the focus text, and save through safeSave. Follow-up todos mirror
//  NewTodoForm.createTodo, including student tag syncing.
//

import CoreData
import Foundation

extension MCPNotebookTools {
    // MARK: - Record Meeting

    static func createMeetingEntryTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "create_meeting_entry",
            title: "Record Student Meeting",
            description: "Record a completed student meeting (conference) in the student's "
                + "history, exactly as the in-app meeting form would: a reflection on how the "
                + "work is going, lessons the student requested, private guide notes, and new "
                + "goals that carry forward to the next meeting as open focus items.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student": [
                        "type": "string",
                        "description": "The student met with: a name or nickname, or a student id from list_students"
                    ],
                    "date": [
                        "type": "string",
                        "description": "Meeting date as YYYY-MM-DD (default today)"
                    ],
                    "reflection": [
                        "type": "string",
                        "description": "How the work is going: plan follow-through, what went well or was hard, social and community notes"
                    ],
                    "lesson_requests": [
                        "type": "string",
                        "description": "Lessons the student asked for or is ready for"
                    ],
                    "guide_notes": [
                        "type": "string",
                        "description": "Private notes only the guide sees"
                    ],
                    "goals": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "New goals or next steps agreed in this meeting; each becomes an open focus item carried to the next conference"
                    ]
                ],
                "required": ["student"]
            ],
            handler: { arguments in
                try recordMeeting(arguments: arguments, in: context())
            }
        )
    }

    @MainActor
    static func recordMeeting(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let reference = try requireString(arguments, "student")
        let student = try resolveStudentReference(reference, in: modelContext)
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }

        let reflection = arguments["reflection"]?.stringValue?.trimmed() ?? ""
        let requests = arguments["lesson_requests"]?.stringValue?.trimmed() ?? ""
        let guideNotes = arguments["guide_notes"]?.stringValue?.trimmed() ?? ""
        let goals = stringArrayArgument(arguments, "goals")
        guard !(reflection.isEmpty && requests.isEmpty && guideNotes.isEmpty && goals.isEmpty) else {
            throw MCPToolError(
                "Provide at least one of reflection, lesson_requests, guide_notes, or goals."
            )
        }
        let date = try dayArgument(arguments, "date") ?? Date()

        // Snapshot carried-forward focus items before adding this meeting's
        // new goals, matching the in-app completion flow.
        let activeItems = FocusItemService.fetchActive(studentID: studentID, context: modelContext)

        let meeting = CDStudentMeeting(context: modelContext)
        meeting.studentIDUUID = studentID
        meeting.date = date
        meeting.completed = true
        meeting.reflection = reflection
        meeting.requests = requests
        meeting.guideNotes = guideNotes
        meeting.focus = FocusItemService.snapshotText(
            activeItems: activeItems, resolvedItems: [], newTexts: goals
        )

        let meetingID = meeting.id ?? UUID()
        for (index, goal) in goals.enumerated() {
            FocusItemService.create(
                studentID: studentID,
                text: goal,
                meetingID: meetingID,
                sortOrder: activeItems.count + index,
                context: modelContext
            )
        }

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The meeting could not be saved.")
        }

        let goalSuffix = goals.isEmpty ? "" : " with \(goals.count) new goal(s)"
        return "Recorded meeting [meeting id=\(meetingID.uuidString)] for \(student.fullName) "
            + "on \(dayString(date))\(goalSuffix)."
    }

    // MARK: - Add Follow-Up

    static func addFollowUpTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "add_follow_up",
            title: "Add Follow-Up",
            description: "Add a follow-up to the guide's todo list — something owed to a "
                + "student, a parent, an assistant, or the guide themself. Optionally tied to "
                + "students and a due date. For a goal a student owns, use the goals field of "
                + "create_meeting_entry instead.",
            inputSchema: [
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
                    ]
                ],
                "required": ["title"]
            ],
            handler: { arguments in
                try addFollowUp(arguments: arguments, in: context())
            }
        )
    }

    @MainActor
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
        let dueDate = try dayArgument(arguments, "due_date")

        let todo = CDTodoItem(context: modelContext)
        todo.title = title
        todo.notes = arguments["notes"]?.stringValue?.trimmed() ?? ""
        todo.studentIDsArray = studentIDs.map(\.uuidString)
        todo.dueDate = dueDate
        todo.tagsArray = TodoTagHelper.syncStudentTags(
            existingTags: [], studentNames: students.map(\.fullName)
        )

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The follow-up could not be saved.")
        }

        var details: [String] = []
        if let dueDate {
            details.append("due \(dayString(dueDate))")
        }
        if !students.isEmpty {
            details.append(students.map(\.fullName).joined(separator: ", "))
        }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"
        let id = todo.id?.uuidString ?? "unknown"
        return "Added follow-up [todo id=\(id)] \"\(title)\"\(suffix)."
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

    @MainActor
    static func resolveFollowUp(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let idString = try requireString(arguments, "id")
        guard let id = UUID(uuidString: idString) else {
            throw MCPToolError("id must be a UUID from list_open_follow_ups.")
        }

        let todoRequest = CDFetchRequest(CDTodoItem.self)
        todoRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let todo = modelContext.safeFetchFirst(todoRequest) {
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

        let focusRequest = CDFetchRequest(CDStudentFocusItem.self)
        focusRequest.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        if let item = modelContext.safeFetchFirst(focusRequest) {
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

    // MARK: - List Open Follow-Ups

    static func listOpenFollowUpsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_open_follow_ups",
            title: "List Open Follow-Ups",
            description: "Everything currently open: the guide's follow-up todos, each "
                + "student's open goals (focus items), and observation notes flagged for "
                + "follow-up. Optionally narrowed to one student.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "Only follow-ups concerning this student (first name, full name, or nickname)"
                    ]
                ]
            ],
            handler: { arguments in
                try listOpenFollowUps(arguments: arguments, in: context())
            }
        )
    }

    @MainActor
    static func listOpenFollowUps(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        var filterID: UUID?
        var filterName = ""
        if let name = arguments["student_name"]?.stringValue?.trimmed(), !name.isEmpty {
            let student = try resolveStudent(named: name, in: modelContext)
            guard let id = student.id else {
                throw MCPToolError("That student record has no identifier.")
            }
            filterID = id
            filterName = student.fullName
        }

        let students = modelContext.safeFetch(CDFetchRequest(CDStudent.self))
        let nameByID = Dictionary(
            students.compactMap { student in student.id.map { ($0.uuidString, student.fullName) } },
            uniquingKeysWith: { first, _ in first }
        )

        var sections: [String] = []

        let todoRequest = CDFetchRequest(CDTodoItem.self)
        todoRequest.predicate = NSPredicate(format: "isCompleted == NO")
        let todos = modelContext.safeFetch(todoRequest)
            .filter { todo in
                guard let filterID else { return true }
                return todo.studentIDsArray.contains(filterID.uuidString)
            }
            .sorted {
                ($0.dueDate ?? .distantFuture, $0.createdAt ?? .distantPast)
                    < ($1.dueDate ?? .distantFuture, $1.createdAt ?? .distantPast)
            }
            .prefix(30)
        if !todos.isEmpty {
            let lines = todos.map { todo -> String in
                var details: [String] = []
                if let dueDate = todo.dueDate {
                    details.append("due \(dayString(dueDate))")
                }
                if todo.isSomeday {
                    details.append("someday")
                }
                let who = todo.studentIDsArray.compactMap { nameByID[$0] }
                if !who.isEmpty {
                    details.append(who.joined(separator: ", "))
                }
                let suffix = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"
                let id = todo.id?.uuidString ?? "unknown"
                return "- [todo id=\(id)] \(todo.title)\(suffix)"
            }
            sections.append("Follow-up todos:\n" + lines.joined(separator: "\n"))
        }

        let focusRequest = CDFetchRequest(CDStudentFocusItem.self)
        focusRequest.predicate = NSPredicate(
            format: "statusRaw == %@", FocusItemStatus.active.rawValue
        )
        let focusItems = modelContext.safeFetch(focusRequest)
            .filter { item in
                guard let filterID else { return true }
                return item.studentIDUUID == filterID
            }
            .sorted {
                (nameByID[$0.studentID] ?? "", $0.sortOrder) < (nameByID[$1.studentID] ?? "", $1.sortOrder)
            }
        if !focusItems.isEmpty {
            let lines = focusItems.map { item -> String in
                let who = nameByID[item.studentID] ?? "Unknown student"
                let id = item.id?.uuidString ?? "unknown"
                return "- [focusItem id=\(id)] \(who): \(item.text)"
            }
            sections.append("Open student goals:\n" + lines.joined(separator: "\n"))
        }

        let noteRequest = CDFetchRequest(CDNote.self)
        noteRequest.predicate = NSPredicate(format: "needsFollowUp == YES")
        noteRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let notes = modelContext.safeFetch(noteRequest)
            .filter { note in
                guard let filterID else { return true }
                return note.scope.applies(to: filterID)
            }
            .prefix(20)
        if !notes.isEmpty {
            let lines = notes.map { note -> String in
                let id = note.id?.uuidString ?? "unknown"
                let body = note.body.count > 200 ? note.body.prefix(200) + "…" : note.body
                return "- [note id=\(id)] \(dayString(note.createdAt)): \(body)"
            }
            sections.append("Notes flagged for follow-up:\n" + lines.joined(separator: "\n"))
        }

        guard !sections.isEmpty else {
            return filterName.isEmpty
                ? "Nothing is open — no follow-up todos, open goals, or flagged notes."
                : "Nothing is open for \(filterName)."
        }
        return sections.joined(separator: "\n\n")
    }

    // MARK: - Shared

    /// Parses an optional YYYY-MM-DD argument, throwing on malformed input.
    static func dayArgument(_ arguments: [String: JSONValue], _ key: String) throws -> Date? {
        guard let dayText = arguments[key]?.stringValue?.trimmed(), !dayText.isEmpty else {
            return nil
        }
        guard let date = isoDay.date(from: dayText) else {
            throw MCPToolError("\(key) must be formatted YYYY-MM-DD, got \"\(dayText)\".")
        }
        return date
    }
}
