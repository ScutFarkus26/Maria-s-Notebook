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
            annotations: .readOnly,
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
            description: "Mark one student present, absent, tardy or left-early on a day, with an optional "
                + "absence reason and note. Pass students for several at once, or mark_all_present to "
                + "mark everyone not named there present. Marks are attributed and sync to the "
                + "classroom.",
            inputSchema: markAttendanceSchema,
            annotations: .idempotentWrite,
            handler: { arguments in
                try markAttendance(arguments: arguments, in: context())
            }
        )
    }

    private static let attendanceStatusSchema: JSONValue = [
        "type": "string",
        "enum": ["present", "absent", "tardy", "leftEarly", "unmarked"],
        "description": "present, absent, tardy, leftEarly, or unmarked"
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
                "description": .string("Mark every enrolled student not named in students "
                    + "present for the day")
            ],
            "date": [
                "type": "string",
                "description": "The day, YYYY-MM-DD (default today)"
            ],
            "absence_reason": [
                "type": "string",
                "enum": ["sick", "vacation", "none"],
                "description": "Only meaningful when the status is absent; single student only"
            ],
            "note": [
                "type": "string",
                "description": "A note about the day (optional); single student only"
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
        let marks = try resolveAttendanceMarks(arguments, in: modelContext)
        guard !marks.isEmpty else {
            throw MCPToolError(
                "No students to mark — pass student_name, students, or mark_all_present."
            )
        }
        return try applyAttendanceMarks(marks, on: day, in: modelContext)
    }

    private static func markOneStudent(
        arguments: [String: JSONValue], on day: Date, in modelContext: NSManagedObjectContext
    ) throws -> String {
        let student = try resolveStudentReference(
            requireString(arguments, "student_name"), in: modelContext
        )
        let status = try attendanceStatus(try requireString(arguments, "status"))

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

    // MARK: - Marking Several At Once

    /// One resolved (student, status) pair. The whole list is built before the
    /// first record is touched, so an unknown or ambiguous name fails the call
    /// with nothing written.
    private struct AttendanceMark {
        let student: CDStudent
        let status: AttendanceStatus
    }

    private static func attendanceStatus(_ raw: String) throws -> AttendanceStatus {
        guard let status = AttendanceStatus(rawValue: raw) else {
            let allowed = AttendanceStatus.allCases.map(\.rawValue).joined(separator: ", ")
            throw MCPToolError("status must be one of: \(allowed). Got \"\(raw)\".")
        }
        return status
    }

    private static func resolveAttendanceMarks(
        _ arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> [AttendanceMark] {
        var marks: [AttendanceMark] = []
        var named: Set<UUID> = []
        for (index, entry) in (arguments["students"]?.arrayValue ?? []).enumerated() {
            guard let item = entry.objectValue else {
                throw MCPToolError(
                    "students[\(index)] must be an object with student_name and status."
                )
            }
            let student = try resolveStudentReference(
                try requireString(item, "student_name"), in: modelContext
            )
            let status = try attendanceStatus(try requireString(item, "status"))
            if let id = student.id { named.insert(id) }
            marks.append(AttendanceMark(student: student, status: status))
        }
        guard arguments["mark_all_present"]?.boolValue == true else { return marks }
        let roster: [CDStudent] = DataQueryService(context: modelContext)
            .fetchAllStudents(excludeTest: true, excludeWithdrawn: true)
        for student in roster {
            guard let id = student.id, !named.contains(id) else { continue }
            marks.append(AttendanceMark(student: student, status: .present))
        }
        return marks
    }

    /// Writes every mark through the same `CDAttendanceStore` the single form
    /// uses — it is what enforces `ClassroomPermissions` and stamps
    /// attribution — then saves once. A refusal rolls the whole call back.
    private static func applyAttendanceMarks(
        _ marks: [AttendanceMark], on day: Date, in modelContext: NSManagedObjectContext
    ) throws -> String {
        let store = CDAttendanceStore(context: modelContext, calendar: AppCalendar.shared)
        var lines: [String] = []
        do {
            for mark in marks {
                guard let record = try store.ensureRecord(for: mark.student, on: day) else {
                    throw MCPToolError(
                        "Attendance could not be written — this classroom role may not have "
                            + "permission to mark attendance."
                    )
                }
                store.updateStatus(record, to: mark.status)
                lines.append("- \(mark.student.fullName) — \(mark.status.displayName.lowercased())")
            }
        } catch {
            modelContext.rollback()
            throw (error as? MCPToolError)
                ?? MCPToolError("Attendance could not be written: \(error.localizedDescription)")
        }
        guard modelContext.safeSave() else {
            modelContext.rollback()
            throw MCPToolError("The attendance marks could not be saved.")
        }
        let tail = "\(marks.count) student(s) marked."
        return (["Attendance for \(dayString(day)):"] + lines.sorted() + [tail])
            .joined(separator: "\n")
    }
}
