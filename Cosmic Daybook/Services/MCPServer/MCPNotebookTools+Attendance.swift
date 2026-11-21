//
//  MCPNotebookTools+Attendance.swift
//  Cosmic Daybook
//
//  Who was in the room, and who wasn't.
//
//  Reads deduplicate with `deduplicatedPerStudentDay()` so MCP counts agree
//  with the grid and the reports rather than double-counting CloudKit
//  duplicates. Writes go through CDAttendanceStore — the chokepoint that
//  enforces ClassroomPermissions, stamps attribution, and assigns new records
//  to the right persistent store. Never write CDAttendanceRecord directly.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    // MARK: - One Day's Attendance

    static func attendanceForDayTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "attendance_for_day",
            title: "Attendance For A Day",
            description: "Who was present, absent, late or left early on a given day, and who "
                + "has not been marked yet.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "date": [
                        "type": "string",
                        "description": "The day, YYYY-MM-DD (default today)"
                    ]
                ]
            ],
            annotations: .readOnly,
            handler: { arguments in
                let modelContext = context()
                let day = AppCalendar.startOfDay(try dayArgument(arguments, "date") ?? Date())
                return describeAttendance(on: day, in: modelContext)
            }
        )
    }

    private static func describeAttendance(
        on day: Date, in modelContext: NSManagedObjectContext
    ) -> String {
        let roster: [CDStudent] = DataQueryService(context: modelContext).fetchAttendanceRoll(on: day)
        guard !roster.isEmpty else { return "No students are enrolled." }

        let grouped: [AttendanceStatus: [String]] = namesByStatus(roster, on: day, in: modelContext)
        let nonSchoolDay: Bool = SchoolCalendarService.shared
            .isNonSchoolDaySync(day, using: modelContext)

        let header: String = "Attendance for " + dayString(day) + " (" + weekdayName(day) + "):"
        var lines: [String] = [header]
        if nonSchoolDay {
            lines.append("  School is not in session that day.")
        }
        lines.append(contentsOf: statusLines(from: grouped))
        let sent = AttendanceEmailLog.thirdPersonSummary(on: day, in: modelContext)
        if AttendanceEmailLog.settings(in: modelContext)?.sendMethod == .parentLocker {
            lines += parentLockerLines(on: day, sent: sent, nonSchoolDay: nonSchoolDay, in: modelContext)
        } else if let sent {
            lines.append("  Front desk email: " + sent)
        }
        return lines.joined(separator: "\n")
    }

    /// With ParentLocker picked: whether the day went, and for today where
    /// this Mac's sending stands, with each child it left alone.
    private static func parentLockerLines(
        on day: Date, sent: String?, nonSchoolDay: Bool, in modelContext: NSManagedObjectContext
    ) -> [String] {
        // A day ParentLocker isn't expecting is no send: said as such.
        let unsent = nonSchoolDay ? "nothing to send"
            : AttendanceEmailLog.isNotExpected(on: day, in: modelContext) ? "not expecting attendance that day"
            : "not sent yet"
        var lines = ["  ParentLocker: " + (sent ?? unsent)]
        guard AppCalendar.shared.isDateInToday(day),
              let status = ParentLockerSync.current(for: modelContext)?.status else { return lines }
        if let message = status.message { lines.append("  ParentLocker on this Mac: " + message) }
        lines.append(contentsOf: status.problems.map { "  - " + $0 })
        return lines
    }

    private static func namesByStatus(
        _ roster: [CDStudent], on day: Date, in modelContext: NSManagedObjectContext
    ) -> [AttendanceStatus: [String]] {
        let ids: [UUID] = roster.compactMap(\.id)
        let statuses: [UUID: AttendanceStatus] = modelContext.attendanceStatuses(for: ids, on: day)
        var grouped: [AttendanceStatus: [String]] = [:]
        for student in roster {
            let status: AttendanceStatus = student.id.flatMap { statuses[$0] } ?? .unmarked
            var names: [String] = grouped[status] ?? []
            names.append(student.fullName)
            grouped[status] = names
        }
        return grouped
    }

    private static func statusLines(from grouped: [AttendanceStatus: [String]]) -> [String] {
        var lines: [String] = []
        for status in AttendanceStatus.allCases {
            let names: [String] = grouped[status] ?? []
            guard !names.isEmpty else { continue }
            let joined: String = names.sorted().joined(separator: ", ")
            let count: String = String(names.count)
            lines.append("  " + status.displayName + " (" + count + "): " + joined)
        }
        return lines
    }

    // MARK: - Marking Attendance

    static func markAttendanceTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "mark_attendance",
            title: "Mark Attendance",
            description: "Mark one student present, absent, late (status tardy) or left early on a day, "
                + "with an optional absence reason and note. Pass students for several at once, and "
                + "mark_all_present to mark present everyone else who has no mark yet: a mark "
                + "already made (by an assistant, say) is kept, and the reply names who kept one. "
                + "The app's rules apply: on a day still to come only absent or unmarked; only "
                + "children on that day's roll; a day off needs confirm_day_off. "
                + "Marks are attributed and sync to the classroom.",
            inputSchema: markAttendanceSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                try undoingOnFailure(context()) { try markAttendance(arguments: arguments, in: $0) }
            }
        )
    }

    private static let attendanceStatusSchema: JSONValue = [
        "type": "string",
        "enum": ["present", "absent", "tardy", "leftEarly", "unmarked"],
        "description": "present, absent, tardy (replies call it late), leftEarly, or unmarked"
    ]

    private static let markAttendanceSchema: JSONValue = [
        "type": "object",
        "properties": [
            "student_name": [
                "type": "string",
                "description": "The student's first name, full name, or nickname"
            ],
            "status": attendanceStatusSchema,
            "students": [
                "type": "array",
                "description": .string("Several students in one call: objects with "
                    + "student_name and status. An unknown or ambiguous name fails the whole "
                    + "call and nothing is written."),
                "items": [
                    "type": "object",
                    "properties": [
                        "student_name": [
                            "type": "string",
                            "description": "The student's first name, full name, or nickname"
                        ],
                        "status": attendanceStatusSchema
                    ],
                    "required": ["student_name", "status"]
                ]
            ],
            "mark_all_present": [
                "type": "boolean",
                "description": .string("Mark present every enrolled student not named in "
                    + "students (or student_name) who has no mark yet for the day; marks already "
                    + "made are kept")
            ],
            "date": [
                "type": "string",
                "description": "The day, YYYY-MM-DD (default today)"
            ],
            "absence_reason": [
                "type": "string",
                "enum": .array(AbsenceReason.allCases.map { .string($0.rawValue) }),
                "description": "Only meaningful when the status is absent; single student only"
            ],
            "note": [
                "type": "string",
                "description": "A note about the day (optional); single student only"
            ],
            "confirm_day_off": [
                "type": "boolean",
                "description": .string("The day has no school (a weekend or a day off), and the guide said to "
                    + "mark it anyway, for a school event, say. Without it a mark on a day off is refused.")
            ]
        ]
    ]

    private static func markAttendance(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let day = AppCalendar.startOfDay(try dayArgument(arguments, "date") ?? Date())
        let wantsBatch = arguments["students"] != nil
            || arguments["mark_all_present"]?.boolValue == true
        guard wantsBatch else {
            return try markOneStudent(arguments: arguments, on: day, in: modelContext)
        }
        guard arguments["absence_reason"] == nil, arguments["note"] == nil else {
            throw MCPToolError(
                "absence_reason and note belong to one student's mark — mark that student on "
                    + "their own call."
            )
        }
        let batch = try resolveAttendanceBatch(arguments, in: modelContext)
        guard !batch.named.isEmpty || batch.markRestPresent else {
            throw MCPToolError(
                "No students to mark — pass student_name, students, or mark_all_present."
            )
        }
        return try applyAttendanceBatch(batch, on: day, in: modelContext)
    }

    private static func markOneStudent(
        arguments: [String: JSONValue], on day: Date, in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudentReference(
            requireString(arguments, "student_name"), in: modelContext
        )
        let status = try attendanceStatus(try requireString(arguments, "status"))
        var reason: AbsenceReason?
        if let reasonRaw = nonEmpty(arguments["absence_reason"]?.stringValue) {
            guard let parsed = AbsenceReason(rawValue: reasonRaw) else {
                let allowed = AbsenceReason.allCases.map(\.rawValue).joined(separator: ", ")
                throw MCPToolError("absence_reason must be one of: \(allowed). Got \"\(reasonRaw)\".")
            }
            // The store takes a reason on an absence only, which is the rule
            // the grid enforces too — say so rather than failing silently.
            guard status == .absent else {
                throw MCPToolError("An absence reason only applies when the status is absent.")
            }
            reason = parsed
        }

        let store = CDAttendanceStore(context: modelContext, calendar: AppCalendar.shared)
        // The store's one mark, with every rule the grids follow (R5).
        let outcome = try markThroughStore(
            store, student: student, status: status, reason: reason, on: day,
            dayOffConfirmed: arguments["confirm_day_off"]?.boolValue == true
        )

        var extras: [String] = []
        if let reason { extras.append(reason.displayName.lowercased()) }
        if let note = nonEmpty(arguments["note"]?.stringValue) {
            // Clearing a child who had no record made none; a note needs one.
            guard let record = try outcome.record ?? store.ensureRecord(for: student, on: day) else {
                throw attendanceRoleRefusal
            }
            store.updateNote(record, to: note)
            extras.append("note filed")
        }

        guard modelContext.safeSave() else {
            throw MCPToolError("The attendance mark could not be saved.")
        }

        let detail = extras.isEmpty ? "" : " (\(extras.joined(separator: ", ")))"
        return "Marked \(student.fullName) \(status.displayName.lowercased()) on "
            + "\(dayString(day))\(detail)."
    }

    static func attendanceStatus(_ raw: String) throws -> AttendanceStatus {
        guard let status = AttendanceStatus(rawValue: raw) else {
            let allowed = AttendanceStatus.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("status must be one of: \(allowed). Got \"\(raw)\".")
        }
        return status
    }
}
