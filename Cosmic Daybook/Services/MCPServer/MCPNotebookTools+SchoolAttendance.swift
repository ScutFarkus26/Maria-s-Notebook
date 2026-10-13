//
//  MCPNotebookTools+SchoolAttendance.swift
//  Cosmic Daybook
//
//  Sending the day's attendance to the school's ParentLocker site (plan
//  "ParentLocker attendance", Phase 3): the one tool that reaches outside the
//  notebook, so it is the one annotated open-world. It sends through
//  `ParentLockerSync`, as the attendance screen's Send Now does, with this
//  Mac's own ParentLocker sign-in; the reply never carries any of it. A
//  preview reads ParentLocker and writes nothing anywhere.
//

import Foundation

/// The ParentLocker sync the tool sends through. Injectable so tests can
/// hand in one on a fake site.
typealias MCPParentLockerProvider = @MainActor @Sendable () -> ParentLockerSync?

extension MCPNotebookTools {

    static func sendAttendanceToSchoolTool(
        parentLocker: @escaping MCPParentLockerProvider = { ParentLockerSync.current }
    ) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "send_attendance_to_school",
            title: "Send Attendance To School",
            description: "Send a day's attendance (default today) to the school's ParentLocker site: "
                + "every child on the day's roll, each in their ParentLocker class, changing only the marks "
                + "that differ there, and record the day as sent. preview: true reads ParentLocker and "
                + "says what would change, sending and recording nothing. Needs ParentLocker picked in the "
                + "app's Settings and this Mac signed in. Children the office locked, children not matched "
                + "yet and unmarked children are left alone and listed.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "date": [
                        "type": "string",
                        "description": "The day, YYYY-MM-DD (default today)"
                    ],
                    "preview": [
                        "type": "boolean",
                        "description": "Read ParentLocker and say what would be sent, sending nothing (default false)"
                    ]
                ]
            ],
            annotations: .outwardSend,
            handler: { arguments in
                let day = AppCalendar.startOfDay(try dayArgument(arguments, "date") ?? Date())
                let preview = arguments["preview"]?.boolValue ?? false
                return try await sendAttendanceToSchool(on: day, preview: preview, sync: parentLocker())
            }
        )
    }

    private static func sendAttendanceToSchool(
        on day: Date, preview: Bool, sync: ParentLockerSync?
    ) async throws -> String {
        if preview { MCPCallOutcome.markNothingWritten() }
        guard let sync else {
            throw MCPToolError("ParentLocker sending isn't running yet. Open Cosmic Daybook and try again.")
        }
        switch await sync.send(day: day, preview: preview) {
        case .success(let report):
            // A test copy of the app (a Debug build) previews whatever it's asked.
            if report.wasPreview { MCPCallOutcome.markNothingWritten() }
            let note = report.wasPreview && !preview
                ? "\nThis copy of the app only previews, so nothing was sent or recorded."
                : ""
            return report.text + note
        case .failure(let failure):
            throw MCPToolError(failure.message)
        }
    }
}
