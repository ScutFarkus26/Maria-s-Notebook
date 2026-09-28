import Foundation

extension MCPNotebookTools {
    /// A locked day takes no marks from anyone — `CDAttendanceStore` refuses
    /// them — so `mark_attendance` says the day is locked rather than blaming
    /// the classroom role.
    static func refuseLockedDay(_ day: Date, store: CDAttendanceStore) throws {
        guard store.isLocked(day) else { return }
        let dayText = day.formatted(date: .complete, time: .omitted)
        throw MCPToolError("Attendance for \(dayText) is locked. Unlock the day in the app first.")
    }
}
