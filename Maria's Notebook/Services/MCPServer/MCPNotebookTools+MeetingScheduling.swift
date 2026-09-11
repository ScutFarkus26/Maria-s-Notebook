//
//  MCPNotebookTools+MeetingScheduling.swift
//  Maria's Notebook
//
//  Booking a student conference that has not happened yet.
//
//  A booking is a CDScheduledMeeting — the record scheduled_meetings reads
//  and the Today agenda shows — written through MeetingScheduler, the path the
//  meetings tab's date picker takes. create_meeting_entry completes it when
//  the meeting is filed, so a conference booked here moves from scheduled to
//  held instead of leaving a stranded booking beside the entry.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - Schedule Meeting

    static func scheduleMeetingTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "schedule_meeting",
            title: "Schedule Meeting",
            description: "Book a student conference that has not happened yet, the way the "
                + "meetings tab's date picker does. It shows in scheduled_meetings and on the "
                + "Today agenda, and is completed rather than duplicated when "
                + "create_meeting_entry files the meeting. A student holds one booking at a "
                + "time: booking another day moves the existing one instead of adding a "
                + "second. A day school is not in session is refused.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student": [
                        "type": "string",
                        "description": .string("The student to meet with: a name or nickname, or a "
                            + "student id from list_students")
                    ],
                    "date": [
                        "type": "string",
                        "description": "The day to meet, YYYY-MM-DD; must be a school day"
                    ],
                    "purpose": [
                        "type": "string",
                        "description": "What the meeting is about, in a phrase"
                    ],
                    "work_id": [
                        "type": "string",
                        "description": "A work item to review in the meeting, by id from student_work"
                    ]
                ],
                "required": ["student", "date"]
            ],
            annotations: .write,
            handler: { arguments in
                try scheduleMeeting(arguments: arguments, in: context())
            }
        )
    }

    private static func scheduleMeeting(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudentReference(requireString(arguments, "student"), in: modelContext)
        guard let studentID = student.id else {
            throw MCPToolError("That student record has no identifier.")
        }
        guard let day = try dayArgument(arguments, "date") else {
            throw MCPToolError("A date is required, formatted YYYY-MM-DD.")
        }
        // The same calendar schedule_for_range consults, so a booking is
        // refused on exactly the days that tool reports as not in session.
        guard !SchoolCalendarService.shared.isNonSchoolDaySync(day, using: modelContext) else {
            throw MCPToolError(
                "School is not in session on \(dayString(day)) (\(weekdayName(day))); "
                    + "nothing was booked. Choose a school day."
            )
        }
        let purpose = nonEmpty(arguments["purpose"]?.stringValue)
        let work = try nonEmpty(arguments["work_id"]?.stringValue)
            .map { try resolveWork($0, in: modelContext) }

        let booking = MeetingScheduler.bookMeeting(
            studentID: studentID,
            date: day,
            purpose: purpose,
            workID: work?.id,
            context: modelContext
        )
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The meeting could not be booked.")
        }
        return receipt(for: booking, student: student, day: day, in: modelContext)
    }

    private static func receipt(
        for booking: (meeting: CDScheduledMeeting, outcome: MeetingScheduler.BookingOutcome),
        student: CDStudent,
        day: Date,
        in modelContext: NSManagedObjectContext
    ) -> String {
        let tag = "[scheduledMeeting id=\(booking.meeting.id?.uuidString ?? "unknown")]"
        var details: [String] = []
        if let purpose = nonEmpty(booking.meeting.purpose) {
            details.append(purpose)
        }
        if let title = workTitle(forID: booking.meeting.workID, in: modelContext) {
            details.append("about \(title)")
        }
        let suffix = details.isEmpty ? "" : " (\(details.joined(separator: "; ")))"

        switch booking.outcome {
        case .created:
            return "Booked \(tag) with \(student.fullName) on \(dayString(day))\(suffix)."
        case .unchanged:
            return "\(student.fullName) was already booked for \(dayString(day)); \(tag) stands\(suffix)."
        case .moved(let from):
            return "\(student.fullName) holds one booking at a time, so \(tag) was moved from "
                + "\(dayString(from)) to \(dayString(day)) rather than a second one made\(suffix)."
        }
    }
}
