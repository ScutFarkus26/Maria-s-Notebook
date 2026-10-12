//
//  MCPNotebookTools+Meetings.swift
//  Cosmic Daybook
//
//  Meeting entries, and the "what is open right now" listing that reads
//  across todos, goals and flagged notes. Entries follow the same save path
//  as the in-app meeting form (MeetingDraftModel.complete): build the
//  CDStudentMeeting, create focus items through FocusItemService, snapshot
//  the focus text, and save through safeSave.
//
//  Adding and resolving a follow-up live in +FollowUps.swift.
//

import CoreData
import Foundation

extension MCPNotebookTools {
    // MARK: - Record Meeting

    static func createMeetingEntryTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "create_meeting_entry",
            title: "Record Student Meeting",
            description: "Record a completed student meeting (conference): a reflection on how the work is "
                + "going, lessons the student requested, private guide notes, and new goals that carry "
                + "forward to the next meeting as open focus items. It completes the student's booking "
                + "for that day (or an earlier one still pending), so the booking leaves "
                + "scheduled_meetings.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student": [
                        "type": "string",
                        "description": "The student met with: a name or nickname, or a student id from list_students"
                    ],
                    "date": [
                        "type": "string",
                        "description": "Meeting date as YYYY-MM-DD (default today); not a day still to come"
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
            annotations: .write,
            handler: { arguments in
                try undoingOnFailure(context()) { try recordMeeting(arguments: arguments, in: $0) }
            }
        )
    }

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
        let date = try heldMeetingDay(arguments)

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

        // Filing the entry for a booked day is the meeting being held, so the
        // booking goes the way the Today agenda sends it on completion
        // (MeetingScheduler.clearMeeting) — otherwise the conference would sit
        // in scheduled_meetings beside its own record.
        let bookedFor = MeetingScheduler.completeBooking(
            studentID: studentID, heldOn: date, context: modelContext
        )

        guard modelContext.safeSave() else {
            throw MCPToolError("The meeting could not be saved.")
        }

        let goalSuffix = goals.isEmpty ? "" : " with \(goals.count) new goal(s)"
        let bookingSuffix = bookedFor.map { ", completing the booking made for \(dayString($0))" } ?? ""
        return "Recorded meeting [meeting id=\(meetingID.uuidString)] for \(student.fullName) "
            + "on \(dayString(date))\(goalSuffix)\(bookingSuffix)."
    }

    /// The `date` argument, today by default. A meeting is recorded once it
    /// has been held: filing one for a day still to come would also complete
    /// every booking up to that day (bug hunt 2026-10-11 #53).
    private static func heldMeetingDay(_ arguments: [String: JSONValue]) throws -> Date {
        let date = try dayArgument(arguments, "date") ?? Date()
        guard AppCalendar.startOfDay(date) <= AppCalendar.startOfDay(Date()) else {
            throw MCPToolError(
                "create_meeting_entry refused — nothing has been changed. \(dayString(date)) hasn't "
                    + "happened yet, and a meeting is recorded after it is held. To put one on the "
                    + "calendar, use schedule_meeting."
            )
        }
        return date
    }

    // MARK: - List Open Follow-Ups

    static func listOpenFollowUpsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "list_open_follow_ups",
            title: "List Open Follow-Ups",
            description: "Everything currently open: the guide's follow-up todos, each "
                + "student's open goals (focus items), and observation notes flagged for "
                + "follow-up. Optionally narrowed to one student, or to the app's Watching "
                + "list. Without a student, goals and notes about children who have left are "
                + "left out.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "Only follow-ups concerning this student (first name, full name, or nickname)"
                    ],
                    "watching_only": [
                        "type": "boolean",
                        "description": .string("Only what the app's Watching list shows — flagged "
                            + "notes, open todos beginning with Watch that name a child, and open "
                            + "goals — grouped per child (default false)")
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                try listOpenFollowUps(arguments: arguments, in: context())
            }
        )
    }

    /// One open todo in `list_open_follow_ups`.
    private static func followUpTodoLine(
        _ todo: CDTodoItem, nameByID: [String: String], workTitles: [String: String]
    ) -> String {
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
        if let work = linkedWorkDetail(of: todo, titles: workTitles) {
            details.append(work)
        }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"
        let id = todo.id?.uuidString ?? "unknown"
        return "- [todo id=\(id)] \(todo.title)\(suffix)"
    }

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

        if arguments["watching_only"]?.boolValue ?? false {
            return listWatching(studentID: filterID, studentName: filterName, in: modelContext)
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
            let workTitles = linkedWorkTitles(for: Array(todos), in: modelContext)
            let lines = todos.map { followUpTodoLine($0, nameByID: nameByID, workTitles: workTitles) }
            sections.append("Follow-up todos:\n" + lines.joined(separator: "\n"))
        }

        let focusRequest = CDFetchRequest(CDStudentFocusItem.self)
        focusRequest.predicate = NSPredicate(
            format: "statusRaw == %@", FocusItemStatus.active.rawValue
        )
        // Named, a child's goals and notes all show, whatever her status.
        // Otherwise only the class as it is now: a goal or a flagged note about
        // a child who left, or a hidden test student, isn't an open thread
        // (bug hunt 2026-10-11 #51).
        let current: Set<UUID> = filterID == nil ? currentRosterIDs(in: modelContext) : []
        let focusItems = modelContext.safeFetch(focusRequest)
            .filter { item in
                guard let filterID else { return item.studentIDUUID.map(current.contains) ?? false }
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
                guard let filterID else { return isAboutCurrentClass(note.scope, roster: current) }
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

    /// The children in the class now, as the app's roster shows them:
    /// enrolled, less the test students hidden in Settings.
    static func currentRosterIDs(in modelContext: NSManagedObjectContext) -> Set<UUID> {
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = CDStudent.enrolledPredicate
        return Set(TestStudentsFilter.filterVisible(modelContext.safeFetch(request)).compactMap(\.id))
    }

    /// A whole-class note always is; one about named children is when any of
    /// them is still here.
    private static func isAboutCurrentClass(_ scope: NoteScope, roster: Set<UUID>) -> Bool {
        switch scope {
        case .all: return true
        case .student(let id): return roster.contains(id)
        case .students(let ids): return ids.contains(where: roster.contains)
        }
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
