import Foundation
import CoreData
import SwiftData

// MARK: - Presentation Absent Helper

/// Helper for determining absent students in a lesson presentation.
enum PresentationAbsentHelper {

    // MARK: - Compute Absent Student IDs

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

    // MARK: - Deprecated SwiftData Bridge

    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    @MainActor
    static func computeAbsentStudentIDs(
        selectedStudentIDs: Set<UUID>,
        scheduledDay: Date,
        modelContext: ModelContext
    ) -> Set<UUID> {
        let cdContext = AppBootstrapping.getSharedCoreDataStack().viewContext
        return computeAbsentStudentIDs(selectedStudentIDs: selectedStudentIDs, scheduledDay: scheduledDay, context: cdContext)
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
