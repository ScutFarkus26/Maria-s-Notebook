import Foundation

// MARK: - Meeting Work Snapshot Helper

/// Helper for computing work statistics for student meetings.
enum MeetingWorkSnapshotHelper {

    // MARK: - Work Statistics

    /// Computes work statistics for a student.
    ///
    /// - Parameters:
    ///   - studentID: Student ID
    ///   - allWorkModels: All work models
    ///   - workOverdueDays: Days after which work is considered overdue
    /// - Returns: Tuple of (open, overdue, recentCompleted) work arrays
    static func computeWorkStats(
        for studentID: UUID,
        allWorkModels: [WorkModel],
        workOverdueDays: Int
    ) -> (open: [WorkModel], overdue: [WorkModel], recentCompleted: [WorkModel]) {
        let sid = studentID.uuidString
        let workModelsForStudent = allWorkModels.filter { $0.studentID == sid }

        let openWork = workModelsForStudent.filter { $0.status != .complete }

        let overdueThreshold = Calendar.current.date(byAdding: .day, value: -workOverdueDays, to: Date()) ?? Date.distantPast
        let overdueWork = workModelsForStudent.filter { $0.status != .complete && $0.createdAt < overdueThreshold }

        let recentThreshold = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        let recentCompleted = workModelsForStudent.filter { $0.status == .complete && ($0.completedAt ?? .distantPast) >= recentThreshold }

        return (open: openWork, overdue: overdueWork, recentCompleted: recentCompleted)
    }

    // MARK: - Lessons Since Last Meeting

    /// Returns lessons given since the last meeting.
    ///
    /// - Parameters:
    ///   - studentID: Student ID
    ///   - lastMeetingDate: Date of the last meeting (nil if no meetings)
    ///   - allStudentLessons: All student lessons
    /// - Returns: Array of StudentLesson given since the last meeting
    static func lessonsSinceLastMeeting(
        for studentID: UUID,
        lastMeetingDate: Date?,
        allStudentLessons: [StudentLesson]
    ) -> [StudentLesson] {
        let studentIDString = studentID.uuidString
        let cutoffDate = lastMeetingDate ?? Date.distantPast

        return allStudentLessons.filter { studentLesson in
            // Check if this student is in the lesson
            guard studentLesson.studentIDs.contains(studentIDString) else { return false }

            // Check if lesson was given after the last meeting
            if let givenAt = studentLesson.givenAt {
                return givenAt > cutoffDate
            }
            // Also check if it was marked as presented after the last meeting
            if studentLesson.isPresented {
                return studentLesson.createdAt > cutoffDate
            }

            return false
        }
    }
}
