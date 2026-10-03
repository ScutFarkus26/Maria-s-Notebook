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

        let overdueThreshold = AppCalendar.shared.date(
            byAdding: .day, value: -workOverdueDays, to: Date()
        ) ?? Date.distantPast

        let notComplete = workModelsForStudent.filter { $0.status.isOpen }

        let overdueWork = notComplete.filter {
            ($0.createdAt ?? Date()) < overdueThreshold && !$0.isResting
        }

        let overdueIDs = Set(overdueWork.compactMap(\.id))
        let openWork = notComplete.filter { work in
            guard let id = work.id else { return true }
            return !overdueIDs.contains(id)
        }

        let recentThreshold = AppCalendar.shared.date(byAdding: .day, value: -7, to: Date()) ?? Date.distantPast
        let recentCompleted = workModelsForStudent.filter {
            $0.status.isClosed && ($0.completedAt ?? .distantPast) >= recentThreshold
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
        // The cutoff is clamped to the school-year counter epoch, so "since the last meeting"
        // never reaches back past the first day of school (see `SchoolYearCounters`).
        let cutoffDate = SchoolYearCounters.countFrom(lastMeetingDate ?? Date.distantPast)

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

    // MARK: - One child's meeting (Meetings workflow)

    /// The meeting's two work lists, from the child's own work rows.
    struct SessionWork {
        /// Open work older than the overdue setting: each needs a decision.
        let stuck: [CDWorkModel]
        let open: [CDWorkModel]
    }

    /// Splits a child's work into stuck and open. An item reviewed in this
    /// meeting stays in its list after its status closes it (or it is set
    /// resting), so the card shows the choice that was made. Work resting
    /// from an earlier decision isn't stuck: it waits with the open work.
    static func sessionWork(
        _ work: [CDWorkModel],
        workOverdueDays: Int,
        reviewed: Set<UUID>,
        now: Date = Date()
    ) -> SessionWork {
        let overdueBefore = AppCalendar.shared.date(byAdding: .day, value: -workOverdueDays, to: now) ?? .distantPast
        let isReviewed = { (item: CDWorkModel) in item.id.map(reviewed.contains) ?? false }
        let shown = work.filter { $0.status.isOpen || isReviewed($0) }
        let stuck = shown.filter {
            ($0.createdAt ?? now) < overdueBefore && (isReviewed($0) || !$0.isResting(asOf: now))
        }
        let stuckIDs = Set(stuck.compactMap(\.id))
        return SessionWork(
            stuck: stuck,
            open: shown.filter { work in work.id.map { !stuckIDs.contains($0) } ?? true }
        )
    }

    /// The fetch for presentations given after `cutoff`, the same rule as
    /// `lessonsSinceLastMeeting`; who was in them is checked in memory
    /// (`studentIDs` is an encoded list a predicate can't read).
    static func lessonsSincePredicate(cutoff: Date) -> NSPredicate {
        NSPredicate(
            format: "presentedAt > %@ OR (presentedAt == nil AND stateRaw == %@ AND createdAt > %@)",
            cutoff as NSDate, LessonAssignmentState.presented.rawValue, cutoff as NSDate
        )
    }
}
