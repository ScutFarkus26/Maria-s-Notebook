//
//  MCPNotebookTools+MeetingReads.swift
//  Maria's Notebook
//
//  Reading back the meetings `create_meeting_entry` files, and the meetings
//  still to come.
//
//  Writing a meeting without being able to read one back left the model
//  filing into a drawer it could not open — it could record what was agreed
//  and then had no way to recall it at the next sitting.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Meeting History

    static func studentMeetingsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "student_meetings",
            title: "Student Meetings",
            description: "A student's meeting history, newest first: what they reflected on, "
                + "what they asked for, the guide's notes, the work reviewed, and whether the "
                + "meeting was completed. Read this before filing a new one with "
                + "create_meeting_entry so the conversation picks up where it left off.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ],
                    "limit": [
                        "type": "integer",
                        "description": "Maximum meetings to return, 1-20 (default 5)"
                    ]
                ],
                "required": ["student_name"]
            ],
            handler: { arguments in
                let modelContext = context()
                let student = try resolveStudentReference(
                    requireString(arguments, "student_name"), in: modelContext
                )
                let limit = intArgument(arguments, "limit", default: 5, range: 1...20)
                return describeMeetings(for: student, limit: limit, in: modelContext)
            }
        )
    }

    private static func describeMeetings(
        for student: CDStudent, limit: Int, in modelContext: NSManagedObjectContext
    ) -> String {
        guard let studentID = student.id else {
            return "That student record has no identifier."
        }
        let request = CDFetchRequest(CDStudentMeeting.self)
        request.predicate = NSPredicate(format: "studentID == %@", studentID.uuidString)
        let meetings: [CDStudentMeeting] = modelContext.safeFetch(request)
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        guard !meetings.isEmpty else {
            return "No meetings are recorded for \(student.fullName)."
        }

        let shown: [CDStudentMeeting] = Array(meetings.prefix(limit))
        var lines: [String] = ["Meetings with \(student.fullName):"]
        for meeting in shown {
            lines.append(contentsOf: meetingLines(meeting, in: modelContext))
        }
        if meetings.count > shown.count {
            lines.append("(\(meetings.count - shown.count) older meeting(s) not shown.)")
        }
        return lines.joined(separator: "\n")
    }

    private static func meetingLines(
        _ meeting: CDStudentMeeting, in modelContext: NSManagedObjectContext
    ) -> [String] {
        let id: String = meeting.id?.uuidString ?? "unknown"
        let state: String = meeting.completed ? "" : " (not finished)"
        var lines: [String] = ["- [meeting id=\(id)] \(dayString(meeting.date))\(state)"]

        for (label, text) in [
            ("Focus", meeting.focus),
            ("Reflection", meeting.reflection),
            ("Asked for", meeting.requests),
            ("Guide notes", meeting.guideNotes)
        ] {
            if let body = nonEmpty(text) {
                lines.append("    \(label): \(body)")
            }
        }

        let reviews: [CDMeetingWorkReview] =
            (meeting.workReviews?.allObjects as? [CDMeetingWorkReview]) ?? []
        for review in reviews {
            let title: String = workTitle(forID: review.workID, in: modelContext) ?? "work"
            let note: String = nonEmpty(review.noteText).map { " — \($0)" } ?? ""
            lines.append("    Reviewed \(title)\(note)")
        }

        let notes: [CDNote] = (meeting.notes?.allObjects as? [CDNote]) ?? []
        for note in notes where !note.body.trimmed().isEmpty {
            let noteID: String = note.id?.uuidString ?? "unknown"
            lines.append("    [note id=\(noteID)] \(note.body.trimmed())")
        }
        return lines
    }

    /// A work review points at its work by id string; naming it keeps the line
    /// readable rather than printing a bare uuid.
    static func workTitle(
        forID workID: String?, in modelContext: NSManagedObjectContext
    ) -> String? {
        guard let workID, let uuid = UUID(uuidString: workID) else { return nil }
        return WorkRepository(context: modelContext).fetchWorkModel(id: uuid).map { title(of: $0) }
    }

    // MARK: - Meetings Still To Come

    static func scheduledMeetingsTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "scheduled_meetings",
            title: "Scheduled Meetings",
            description: "Student meetings booked but not yet held, with who is coming, what "
                + "each is about, and the work it will review. schedule_for_range does not "
                + "include these; schedule_meeting books one.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "start_date": [
                        "type": "string",
                        "description": "Earliest day to include, YYYY-MM-DD (default today)"
                    ],
                    "end_date": [
                        "type": "string",
                        "description": "Latest day to include, YYYY-MM-DD (default: no limit)"
                    ],
                    "student_name": [
                        "type": "string",
                        "description": "Only meetings involving this student"
                    ]
                ]
            ],
            handler: { arguments in
                try describeScheduledMeetings(arguments: arguments, in: context())
            }
        )
    }

    private static func describeScheduledMeetings(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let start: Date = AppCalendar.startOfDay(try dayArgument(arguments, "start_date") ?? Date())
        let end: Date? = try dayArgument(arguments, "end_date")
        let student = try nonEmpty(arguments["student_name"]?.stringValue)
            .map { try resolveStudentReference($0, in: modelContext) }
        let studentKey: String? = student?.id?.uuidString

        let all: [CDScheduledMeeting] = modelContext.safeFetch(CDFetchRequest(CDScheduledMeeting.self))
        var kept: [CDScheduledMeeting] = []
        for meeting in all {
            guard let date = meeting.date, AppCalendar.startOfDay(date) >= start else { continue }
            if let end, AppCalendar.startOfDay(date) > AppCalendar.startOfDay(end) { continue }
            if let studentKey, !involvesStudent(meeting, key: studentKey) { continue }
            kept.append(meeting)
        }
        guard !kept.isEmpty else {
            let who = student.map { " for \($0.fullName)" } ?? ""
            return "No meetings are scheduled\(who) from \(dayString(start)) onward."
        }

        let names = studentNameIndex(in: modelContext)
        let sorted: [CDScheduledMeeting] = kept.sorted {
            ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture)
        }
        let lines = sorted.map { meeting -> String in
            let id: String = meeting.id?.uuidString ?? "unknown"
            let who: [String] = participantKeys(of: meeting).compactMap { names[$0] }.sorted()
            var details: [String] = [who.isEmpty ? "no students linked" : who.joined(separator: ", ")]
            if meeting.isGroupMeeting {
                details.append("group meeting")
            }
            if let purpose = nonEmpty(meeting.purpose) {
                details.append(purpose)
            }
            if let workID = meeting.workID, let title = workTitle(forID: workID, in: modelContext) {
                details.append("about \(title)")
            }
            return "- [scheduledMeeting id=\(id)] \(dayString(meeting.date)) — "
                + details.joined(separator: "; ")
        }
        return "\(sorted.count) scheduled meeting(s):\n" + lines.joined(separator: "\n")
    }

    /// `allStudentIDs` already resolves a single sitting to its one student and
    /// a group sitting to its participant list.
    private static func participantKeys(of meeting: CDScheduledMeeting) -> [String] {
        meeting.allStudentIDs
    }

    private static func involvesStudent(_ meeting: CDScheduledMeeting, key: String) -> Bool {
        participantKeys(of: meeting).contains(key)
    }
}
