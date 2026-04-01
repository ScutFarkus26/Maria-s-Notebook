import Foundation
import CoreData

// MARK: - Presentation Absent Helper

/// Helper for determining absent students in a lesson presentation.
enum PresentationAbsentHelper {

    // MARK: - Compute Absent CDStudent IDs

    /// Computes the set of student IDs that are marked absent for the scheduled day.
    static func computeAbsentStudentIDs(
        selectedStudentIDs: Set<UUID>,
        scheduledDay: Date,
        context: NSManagedObjectContext
    ) -> Set<UUID> {
        let statuses = context.attendanceStatuses(for: Array(selectedStudentIDs), on: scheduledDay)
        return Set(statuses.compactMap { (key: UUID, value: AttendanceStatus) in
            value == .absent ? key : nil
        })
    }

    // MARK: - Can Move Absent Students

    /// Determines if moving absent students is available.
    static func canMoveAbsentStudents(
        studentCount: Int,
        isPresented: Bool,
        absentStudentIDs: Set<UUID>
    ) -> Bool {
        studentCount > 1 && !isPresented && !absentStudentIDs.isEmpty
    }
}
