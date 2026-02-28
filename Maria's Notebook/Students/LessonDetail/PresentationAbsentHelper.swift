import Foundation
import SwiftData

// MARK: - Presentation Absent Helper

/// Helper for determining absent students in a lesson presentation.
enum PresentationAbsentHelper {

    // MARK: - Compute Absent Student IDs

    /// Computes the set of student IDs that are marked absent for the scheduled day.
    ///
    /// - Parameters:
    ///   - selectedStudentIDs: The set of selected student IDs
    ///   - scheduledDay: The day to check attendance for
    ///   - modelContext: Model context for fetching attendance data
    /// - Returns: Set of student IDs that are absent
    static func computeAbsentStudentIDs(
        selectedStudentIDs: Set<UUID>,
        scheduledDay: Date,
        modelContext: ModelContext
    ) -> Set<UUID> {
        let statuses = modelContext.attendanceStatuses(for: Array(selectedStudentIDs), on: scheduledDay)
        return Set(statuses.compactMap { (key: UUID, value: AttendanceStatus) in
            value == .absent ? key : nil
        })
    }

    // MARK: - Can Move Absent Students

    /// Determines if moving absent students is available.
    ///
    /// - Parameters:
    ///   - studentCount: Number of selected students
    ///   - isPresented: Whether the lesson is already presented
    ///   - absentStudentIDs: Set of absent student IDs
    /// - Returns: True if moving absent students is available
    static func canMoveAbsentStudents(
        studentCount: Int,
        isPresented: Bool,
        absentStudentIDs: Set<UUID>
    ) -> Bool {
        studentCount > 1 && !isPresented && !absentStudentIDs.isEmpty
    }
}
