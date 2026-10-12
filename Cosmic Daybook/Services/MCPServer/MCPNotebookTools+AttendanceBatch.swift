//
//  MCPNotebookTools+AttendanceBatch.swift
//  Cosmic Daybook
//
//  `mark_attendance` for several children at once: the named marks, then
//  everyone else on the roll who has no mark yet marked present. A mark
//  already made (an assistant's absence at 8:15, a child who left early) is
//  kept, as the app's Mark Everyone Present keeps it. Writes go through
//  CDAttendanceStore, like the single form in MCPNotebookTools+Attendance.swift.
//

import CoreData
import Foundation

extension MCPNotebookTools {

    /// One resolved (student, status) pair. The whole list is built before the
    /// first record is touched, so an unknown or ambiguous name fails the call
    /// with nothing written.
    struct AttendanceMark {
        let student: CDStudent
        let status: AttendanceStatus
    }

    /// The named marks, and whether everyone else still unmarked is to be
    /// marked present.
    struct AttendanceBatch {
        let named: [AttendanceMark]
        let markRestPresent: Bool
    }

    /// The named marks: `students`, plus a top-level `student_name` and
    /// `status` given beside them or beside `mark_all_present` ("Maya's
    /// absent, everyone else is here"), which used to be ignored, so the
    /// named child was marked present with everyone else.
    static func resolveAttendanceBatch(
        _ arguments: [String: JSONValue], in modelContext: NSManagedObjectContext
    ) throws -> AttendanceBatch {
        var marks: [AttendanceMark] = []
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
            marks.append(AttendanceMark(student: student, status: status))
        }
        let topName = nonEmpty(arguments["student_name"]?.stringValue)
        var topStatus = nonEmpty(arguments["status"]?.stringValue)
        // A lone "present" with no child named is "everyone's here" said
        // twice, which the batch already does; it is ignored. Any other lone
        // status can't be placed, and is refused below.
        if topName == nil, let lone = topStatus, try attendanceStatus(lone) == .present {
            topStatus = nil
        }
        if topName != nil || topStatus != nil {
            guard let topName, let topStatus else {
                throw MCPToolError(
                    "student_name and status go together — pass both for that child, or put "
                        + "every child in students with their own status."
                )
            }
            let student = try resolveStudentReference(topName, in: modelContext)
            marks.append(AttendanceMark(student: student, status: try attendanceStatus(topStatus)))
        }
        return AttendanceBatch(
            named: try oneMarkPerChild(marks), markRestPresent: arguments["mark_all_present"]?.boolValue == true
        )
    }

    /// A child named twice with the same status is one mark, so the reply and
    /// its count match what is saved. Named with two statuses, the call can't
    /// say which is meant (the second used to overwrite the first while both
    /// were reported) and is refused before anything is written.
    private static func oneMarkPerChild(_ marks: [AttendanceMark]) throws -> [AttendanceMark] {
        var kept: [AttendanceMark] = []
        for mark in marks {
            guard let earlier = kept.first(where: { $0.student === mark.student }) else {
                kept.append(mark)
                continue
            }
            guard earlier.status == mark.status else {
                throw MCPToolError(
                    "\(mark.student.fullName) is named twice, as \(earlier.status.displayName.lowercased()) "
                        + "and as \(mark.status.displayName.lowercased()). Nothing has been changed. Give each "
                        + "child one status."
                )
            }
        }
        return kept
    }

    /// Writes the named marks through the same `CDAttendanceStore` the single
    /// form uses (it enforces `ClassroomPermissions` and stamps attribution),
    /// then marks the rest of the roll present with the store's own
    /// `markUnmarkedPresent`, which keeps any mark already made — the app's
    /// Mark Everyone Present. Saves once; a refusal rolls the whole call back.
    static func applyAttendanceBatch(
        _ batch: AttendanceBatch, on day: Date, in modelContext: NSManagedObjectContext
    ) throws -> String {
        let store = CDAttendanceStore(context: modelContext, calendar: AppCalendar.shared)
        try refuseLockedDay(day, store: store)
        // `markUnmarkedPresent` does nothing, silently, for a role that may not
        // mark attendance; say so rather than reporting nobody marked. Every
        // classroom role may mark attendance today (`ClassroomPermissions`:
        // the guide writes everything, an assistant writes attendance), so
        // this only fires if a role without it is ever added. It stays as the
        // defense against that silent no-op.
        guard store.canWrite(on: day) else { throw attendanceRoleRefusal }
        var lines: [String] = []
        var named: Set<UUID> = []
        var kept: [String] = []
        do {
            for mark in batch.named {
                guard let record = try store.ensureRecord(for: mark.student, on: day) else {
                    throw attendanceRoleRefusal
                }
                store.updateStatus(record, to: mark.status)
                if let id = mark.student.id { named.insert(id) }
                lines.append("- \(mark.student.fullName) — \(mark.status.displayName.lowercased())")
            }
            if batch.markRestPresent {
                let rest = try markRestPresent(on: day, except: named, store: store, in: modelContext)
                lines += rest.marked
                kept = rest.kept
            }
        } catch {
            throw (error as? MCPToolError)
                ?? MCPToolError("Attendance could not be written", underlying: error)
        }
        guard !lines.isEmpty else {
            MCPCallOutcome.markNothingWritten()
            let keptText = kept.isEmpty ? "" : " Already marked: \(kept.sorted().joined(separator: ", "))."
            return "Nothing to mark for \(dayString(day)) — everyone on the roll already has a mark."
                + keptText
        }
        guard modelContext.safeSave() else {
            throw MCPToolError("The attendance marks could not be saved.")
        }
        var reply = ["Attendance for \(dayString(day)):"] + lines.sorted()
        if !kept.isEmpty {
            reply.append("Already marked, left as they were: \(kept.sorted().joined(separator: ", ")).")
        }
        reply.append("\(lines.count) student(s) marked.")
        return reply.joined(separator: "\n")
    }

    /// The roll's other children marked present with the store's own
    /// `markUnmarkedPresent`, which leaves anyone already marked as she was.
    /// Returns a reply line for each child it marked and "Name (status)" for
    /// each who kept an earlier mark.
    private static func markRestPresent(
        on day: Date, except named: Set<UUID>, store: CDAttendanceStore,
        in modelContext: NSManagedObjectContext
    ) throws -> (marked: [String], kept: [String]) {
        let rest = DataQueryService(context: modelContext).fetchAttendanceRoll(on: day)
            .filter { student in student.id.map { !named.contains($0) } ?? false }
        let markedIDs = Set(try store.markUnmarkedPresent(for: day, students: rest).map(\.studentID))
        let statuses = modelContext.attendanceStatuses(for: rest.compactMap(\.id), on: day)
        var marked: [String] = []
        var kept: [String] = []
        for student in rest {
            guard let id = student.id else { continue }
            if markedIDs.contains(id.uuidString) {
                marked.append("- \(student.fullName) — present")
            } else if let status = statuses[id], status != .unmarked {
                kept.append("\(student.fullName) (\(status.displayName.lowercased()))")
            }
        }
        return (marked, kept)
    }

    private static var attendanceRoleRefusal: MCPToolError {
        MCPToolError(
            "Attendance could not be written — this classroom role may not have permission "
                + "to mark attendance."
        )
    }
}
