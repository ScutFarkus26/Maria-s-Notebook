import Foundation

extension MCPNotebookTools {
    /// A locked day takes no marks from anyone — `CDAttendanceStore` refuses
    /// them — so `mark_attendance` says the day is locked rather than blaming
    /// the classroom role.
    static func refuseLockedDay(_ day: Date, store: CDAttendanceStore) throws {
        guard store.isLocked(day) else { return }
        throw lockedDayRefusal(day)
    }

    private static func lockedDayRefusal(_ day: Date) -> MCPToolError {
        let dayText = day.formatted(date: .complete, time: .omitted)
        return MCPToolError("Attendance for \(dayText) is locked. Unlock the day in the app first.")
    }

    static var attendanceRoleRefusal: MCPToolError {
        MCPToolError(
            "Attendance could not be written — this classroom role may not have permission "
                + "to mark attendance."
        )
    }

    /// One child's mark through the store's `mark(student:status:reason:on:)`,
    /// which holds every rule the grids do (domain-logic review R5), with
    /// its refusals said as Claude needs them: what was refused and why,
    /// nothing written.
    @discardableResult
    static func markThroughStore(
        _ store: CDAttendanceStore,
        student: CDStudent,
        status: AttendanceStatus,
        reason: AbsenceReason? = nil,
        on day: Date,
        dayOffConfirmed: Bool
    ) throws -> AttendanceMarkOutcome {
        do {
            return try store.mark(
                student: student, status: status, reason: reason, on: day, dayOffConfirmed: dayOffConfirmed
            )
        } catch let refusal as AttendanceMarkRefusal {
            throw attendanceRefusal(refusal, student: student, status: status, on: day)
        } catch {
            throw MCPToolError("Attendance could not be written", underlying: error)
        }
    }

    /// Why a mark was refused, for Claude to pass on.
    static func attendanceRefusal(
        _ refusal: AttendanceMarkRefusal, student: CDStudent?, status: AttendanceStatus, on day: Date
    ) -> MCPToolError {
        let name = student?.fullName ?? "That child"
        let dayText = dayString(day)
        switch refusal {
        case .roleCannotWrite:
            return attendanceRoleRefusal
        case .locked:
            return lockedDayRefusal(day)
        case .notOnRoll(.notStarted):
            return MCPToolError("\(name) hasn't started yet on \(dayText), so nothing was marked.")
        case .notOnRoll(.departed):
            return MCPToolError("\(name) had left the class before \(dayText), so nothing was marked.")
        case .notOnRoll(.testStudent):
            return MCPToolError("\(name) is hidden as a test student, so nothing was marked.")
        case .aheadOfDay:
            return MCPToolError(
                "\(dayText) hasn't come yet. Ahead of the day only an absence (or clearing a mark) can be "
                    + "recorded, so \(status.displayName.lowercased()) was not marked. Nothing was changed."
            )
        case .dayOff:
            return MCPToolError(
                "\(dayText) (\(weekdayName(day))) has no school, so nothing was marked. If school really "
                    + "meets that day, check with the guide, then call again with confirm_day_off: true."
            )
        }
    }
}
