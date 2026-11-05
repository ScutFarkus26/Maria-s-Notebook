//
//  MCPNotebookTools+MeetingReads.swift
//  Cosmic Daybook
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
            annotations: .readOnly,
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
