// MCPNotebookTools+StudentEnrollment.swift
// update_student's enrollment half: a child leaving the class or coming
// back, through the one write of status and last day
// (`StudentRepository.updateEnrollment`), so Claude's departure runs the
// same cascade the student page offers (domain logic review R7).

import CoreData
import Foundation

extension MCPNotebookTools {

    struct EnrollmentEdit {
        let status: CDStudent.EnrollmentStatus
        let lastDay: Date?
    }

    /// `enrollment` and `last_day`, or nil when the call passes neither. A
    /// `last_day` alone moves a departed child's last day; on an enrolled
    /// child it is refused, since she hasn't left.
    static func parseEnrollment(
        from arguments: [String: JSONValue], for student: CDStudent
    ) throws -> EnrollmentEdit? {
        let statusText = nonEmpty(arguments["enrollment"]?.stringValue)
        let dayText = nonEmpty(arguments["last_day"]?.stringValue)
        guard statusText != nil || dayText != nil else { return nil }
        var status = student.enrollmentStatus
        if let statusText {
            guard let parsed = CDStudent.EnrollmentStatus.allCases.first(
                where: { $0.rawValue.lowercased() == statusText.lowercased() }
            ) else {
                let allowed = CDStudent.EnrollmentStatus.allCases.map(\.rawValue).joined(separator: ", ")
                throw MCPToolError("enrollment must be one of: \(allowed). Got \"\(statusText)\".")
            }
            status = parsed
        }
        var lastDay: Date?
        if let dayText {
            guard let day = isoDay.date(from: dayText) else {
                throw MCPToolError("last_day must be formatted YYYY-MM-DD, got \"\(dayText)\".")
            }
            guard status != .enrolled else {
                throw MCPToolError(
                    "\(student.fullName) is enrolled, so there is no last day to set. "
                        + "Pass enrollment \"withdrawn\" or \"transferred\" with it."
                )
            }
            lastDay = day
        }
        return EnrollmentEdit(status: status, lastDay: lastDay)
    }

    /// The enrollment change in the reply's words.
    static func enrollmentDescriptions(
        _ student: CDStudent, change: StudentRepository.EnrollmentChange
    ) -> [String] {
        guard student.enrollmentStatus != .enrolled else {
            let restored = change.entriesRestored
            let noun = restored == 1 ? "entry" : "entries"
            let back = restored > 0 ? " (\(restored) year-plan \(noun) back to planned)" : ""
            return ["enrolled" + back]
        }
        let lastDay = dayString(student.dateWithdrawn)
        var lines = ["\(student.enrollmentStatus.rawValue), last day \(lastDay)"]
        guard let report = change.departure else { return lines }
        let plans = report.plans.plansEdited + report.plans.plansDeleted
        if plans > 0 { lines.append("off \(plans) planned \(plans == 1 ? "lesson" : "lessons")") }
        let skipped = report.entriesSkipped
        if skipped > 0 { lines.append("\(skipped) year-plan \(skipped == 1 ? "entry" : "entries") skipped") }
        if report.groupsChanged > 0 { lines.append("out of \(report.groupsChanged) schedule groups") }
        if report.workClosed > 0 { lines.append("\(report.workClosed) open work closed as Incomplete") }
        return lines
    }
}
