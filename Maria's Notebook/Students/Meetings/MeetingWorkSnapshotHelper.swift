import Foundation

// MARK: - Meeting Work Snapshot Helper

/// Helper for computing work statistics for student meetings.
enum MeetingWorkSnapshotHelper {

    // MARK: - Types

    struct WorkStats {
        let open: [CDWorkModel]
        let overdue: [CDWorkModel]
        let recentCompleted: [CDWorkModel]
    }

    // MARK: - Work Statistics

    /// Computes work statistics for a student.
    static func computeWorkStats(
        for studentID: UUID,
        allWorkModels: [CDWorkModel],
        workOverdueDays: Int
    ) -> WorkStats {
        let sid = studentID.uuidString
        let workModelsForStudent = allWorkModels.filter { $0.studentID == sid }

        let openWork = workModelsForStudent.filter { $0.status != .complete }

        let overdueThreshold = Calendar.current.date(
            byAdding: .day, value: -workOverdueDays, to: Date()
        ) ?? Date.distantPast
        let overdueWork = workModelsForStudent.filter {
            $0.status != .complete && ($0.createdAt ?? Date()) < overdueThreshold
        }

        let recentThreshold = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        let recentCompleted = workModelsForStudent.filter {
            $0.status == .complete && ($0.completedAt ?? .distantPast) >= recentThreshold
        }

        return WorkStats(open: openWork, overdue: overdueWork, recentCompleted: recentCompleted)
    }

    // MARK: - Lessons Since Last Meeting

    /// Returns lessons given since the last meeting.
    ///
    /// - Parameters:
    ///   - studentID: CDStudent ID
    ///   - lastMeetingDate: Date of the last meeting (nil if no meetings)
    ///   - allLessonAssignments: All lesson assignments
    /// - Returns: Array of CDLessonAssignment given since the last meeting
    static func lessonsSinceLastMeeting(
        for studentID: UUID,
        lastMeetingDate: Date?,
        allLessonAssignments: [CDLessonAssignment]
    ) -> [CDLessonAssignment] {
        let studentIDString = studentID.uuidString
        let cutoffDate = lastMeetingDate ?? Date.distantPast

        return allLessonAssignments.filter { la in
            // Check if this student is in the lesson
            guard la.studentIDs.contains(studentIDString) else { return false }

            // Check if lesson was given after the last meeting
            if let presentedAt = la.presentedAt {
                return presentedAt > cutoffDate
            }
            // Also check if it was marked as presented after the last meeting
            if la.isPresented {
                return (la.createdAt ?? .distantPast) > cutoffDate
            }

            return false
        }
    }
}
