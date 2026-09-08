//
//  MCPNotebookTools+Attendance.swift
//  Maria's Notebook
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
            description: "Who was present, absent, tardy or left early on a given day, and who "
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
        let roster: [CDStudent] = DataQueryService(context: modelContext)
            .fetchAllStudents(excludeTest: true, excludeWithdrawn: true)
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
        return lines.joined(separator: "\n")
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

    // MARK: - One Student's History

    static func studentAttendanceTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "student_attendance",
            title: "Student Attendance",
            description: "One student's attendance over the last N days: a tally, then every day "
                + "they were not simply present.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ],
                    "days_back": [
                        "type": "integer",
                        "description": "How many days back to look, 1-365 (default 30)"
                    ]
                ],
                "required": ["student_name"]
            ],
            handler: { arguments in
                let modelContext = context()
                let student = try resolveStudentReference(
                    requireString(arguments, "student_name"), in: modelContext
                )
                guard let studentID = student.id else {
                    throw MCPToolError("That student record has no identifier.")
                }
                let daysBack = intArgument(arguments, "days_back", default: 30, range: 1...365)
                return describeAttendanceHistory(
                    student: student, studentID: studentID, daysBack: daysBack, in: modelContext
                )
            }
        )
    }

    private static func describeAttendanceHistory(
        student: CDStudent, studentID: UUID, daysBack: Int,
        in modelContext: NSManagedObjectContext
    ) -> String {
        let cutoff = AppCalendar.shared.date(
            byAdding: .day, value: -daysBack, to: AppCalendar.startOfDay(Date())
        ) ?? Date.distantPast

        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND date >= %@", studentID.uuidString, cutoff as NSDate
        )
        let records = modelContext.safeFetch(request)
            .deduplicatedPerStudentDay()
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }

        guard !records.isEmpty else {
            return "No attendance is recorded for \(student.fullName) in the last \(daysBack) days."
        }

        var tally: [AttendanceStatus: Int] = [:]
        for record in records {
            tally[record.status, default: 0] += 1
        }
        let summary = AttendanceStatus.allCases.compactMap { status -> String? in
            guard let count = tally[status], count > 0 else { return nil }
            return "\(count) \(status.displayName.lowercased())"
        }.joined(separator: ", ")

        var lines = ["\(student.fullName), last \(daysBack) days: \(summary)."]
        let notable = records.filter { $0.status != .present && $0.status != .unmarked }
        if !notable.isEmpty {
            lines.append("Days away or late:")
            lines.append(contentsOf: notable.map { record in
                let reason = record.status == .absent && record.absenceReason != .none
                    ? " (\(record.absenceReason.displayName.lowercased()))"
                    : ""
                let note = nonEmpty(record.latestUnifiedNoteText).map { " — \($0)" } ?? ""
                return "- \(dayString(record.date)) \(record.status.displayName.lowercased())\(reason)\(note)"
            })
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Marking Attendance

    static func markAttendanceTool(context: @escaping MCPContextProvider) -> MCPToolDefinition {
        MCPToolDefinition(
            name: "mark_attendance",
            title: "Mark Attendance",
            description: "Mark one student present, absent, tardy or left-early on a day, "
                + "with an optional absence reason and note. Writes through the same store the "
                + "attendance grid uses, so the mark is attributed and syncs to the classroom.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "student_name": [
                        "type": "string",
                        "description": "The student's first name, full name, or nickname"
                    ],
                    "status": [
                        "type": "string",
                        "enum": ["present", "absent", "tardy", "leftEarly", "unmarked"],
                        "description": "present, absent, tardy, leftEarly, or unmarked"
                    ],
                    "date": [
                        "type": "string",
                        "description": "The day, YYYY-MM-DD (default today)"
                    ],
                    "absence_reason": [
                        "type": "string",
                        "enum": ["sick", "vacation", "none"],
                        "description": "Only meaningful when the status is absent"
                    ],
                    "note": [
                        "type": "string",
                        "description": "A note about the day (optional)"
                    ]
                ],
                "required": ["student_name", "status"]
            ],
            handler: { arguments in
                try markAttendance(arguments: arguments, in: context())
            }
        )
    }

    private static func markAttendance(
        arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudentReference(
            requireString(arguments, "student_name"), in: modelContext
        )
        let statusRaw = try requireString(arguments, "status")
        guard let status = AttendanceStatus(rawValue: statusRaw) else {
            let allowed = AttendanceStatus.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("status must be one of: \(allowed). Got \"\(statusRaw)\".")
        }
        let day = AppCalendar.startOfDay(try dayArgument(arguments, "date") ?? Date())

        let store = CDAttendanceStore(context: modelContext, calendar: AppCalendar.shared)
        guard let record = try store.ensureRecord(for: student, on: day) else {
            throw MCPToolError(
                "Attendance could not be written — this classroom role may not have permission "
                    + "to mark attendance."
            )
        }
        store.updateStatus(record, to: status)

        var extras: [String] = []
        if let reasonRaw = nonEmpty(arguments["absence_reason"]?.stringValue) {
            guard let reason = AbsenceReason(rawValue: reasonRaw) else {
                let allowed = AbsenceReason.allCases.map(\.rawValue).joined(separator: ", ")
                throw MCPToolError("absence_reason must be one of: \(allowed). Got \"\(reasonRaw)\".")
            }
            // The store refuses a reason on a status other than absent, which is
            // the rule the grid enforces too — say so rather than failing silently.
            guard status == .absent else {
                throw MCPToolError("An absence reason only applies when the status is absent.")
            }
            store.updateAbsenceReason(record, to: reason)
            extras.append(reason.displayName.lowercased())
        }
        if let note = nonEmpty(arguments["note"]?.stringValue) {
            store.updateNote(record, to: note)
            extras.append("note filed")
        }

        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The attendance mark could not be saved.")
        }

        let detail = extras.isEmpty ? "" : " (\(extras.joined(separator: ", ")))"
        return "Marked \(student.fullName) \(status.displayName.lowercased()) on "
            + "\(dayString(day))\(detail)."
    }
}
