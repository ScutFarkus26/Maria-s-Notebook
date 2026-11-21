import Foundation
import CoreData

extension AttendanceViewModel {
    /// The store's one mark (`CDAttendanceStore.mark(student:…)`), which
    /// holds the roll, the lock, the day-ahead rule and the day off for
    /// every path (domain-logic review R5). Clearing goes through every copy
    /// of the day, and Absent makes Close Arrival's automatic absence the
    /// guide's. The roll shows its day-off warning above the tiles, so a
    /// mark on a day off is taken as meant. Returns the record when
    /// something changed; a refusal is said on the roll (`problem`).
    func mark(
        _ row: AttendanceRow, _ status: AttendanceStatus, reason: AbsenceReason? = nil,
        _ modelContext: NSManagedObjectContext
    ) -> CDAttendanceRecord? {
        do {
            let outcome = try CDAttendanceStore(context: modelContext).mark(
                student: row.student, status: status, reason: reason, on: selectedDate, dayOffConfirmed: true
            )
            return outcome.changed ? outcome.record : nil
        } catch let refusal as AttendanceMarkRefusal {
            show(refusal.userMessage)
            return nil
        } catch {
            report("Couldn't save that mark. Try again.", error, while: "marking")
            return nil
        }
    }
}
