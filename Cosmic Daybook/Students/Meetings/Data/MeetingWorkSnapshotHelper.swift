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
        let cutoffDay = sinceDay(SchoolYearCounters.countFrom(lastMeetingDate ?? Date.distantPast))

        return allLessonAssignments.filter { la in
            // Check if this student is in the lesson
            guard la.studentIDs.contains(studentIDString) else { return false }

            // Check if lesson was given on or after the last meeting's day
            if let presentedAt = la.presentedAt {
                return presentedAt >= cutoffDay
            }
            // Also check if it was marked as presented on or after that day
            if la.isPresented {
                return (la.createdAt ?? .distantPast) >= cutoffDay
            }

            return false
        }
    }

    /// Lessons since a meeting count by day: a given lesson is often stored
    /// at the start of its day, so one given later on the meeting's day read
    /// as before the meeting and was left out (bug hunt 2026-10-10, Part 2
    /// #71). A lesson given earlier that day counts too.
    private static func sinceDay(_ cutoff: Date) -> Date {
        AppCalendar.startOfDay(cutoff)
    }

    // MARK: - One child's meeting (Meetings workflow)

    /// The meeting's work lists, from the child's own work rows.
    struct SessionWork {
        /// Open work older than the overdue setting: each needs a decision.
        let stuck: [CDWorkModel]
        let open: [CDWorkModel]
        /// Her reports, open or resting, in a section of their own: a report
        /// takes weeks, so it's never stuck (2026-10-30).
        var reports: [CDWorkModel] = []
    }

    /// Splits a child's work into stuck, open and reports. An item reviewed
    /// in this meeting stays in its list after its status closes it (or it
    /// is set resting), so the card shows the choice that was made. Work
    /// resting from an earlier decision isn't stuck: it waits with the open
    /// work.
    static func sessionWork(
        _ work: [CDWorkModel],
        workOverdueDays: Int,
        reviewed: Set<UUID>,
        now: Date = Date()
    ) -> SessionWork {
        let overdueBefore = AppCalendar.shared.date(byAdding: .day, value: -workOverdueDays, to: now) ?? .distantPast
        let isReviewed = { (item: CDWorkModel) in item.id.map(reviewed.contains) ?? false }
        let visible = work.filter { $0.status.isOpen || isReviewed($0) }
        let reports = visible.filter(ReportStages.isReport)
        let shown = visible.filter { !ReportStages.isReport($0) }
        let stuck = shown.filter {
            ($0.createdAt ?? now) < overdueBefore && (isReviewed($0) || !$0.isResting(asOf: now))
        }
        let stuckIDs = Set(stuck.compactMap(\.id))
        return SessionWork(
            stuck: stuck,
            open: shown.filter { work in work.id.map { !stuckIDs.contains($0) } ?? true },
            reports: reports.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        )
    }

    /// The fetch for presentations given on or after `cutoff`'s day, the same
    /// rule as `lessonsSinceLastMeeting`; who was in them is checked in memory
    /// (`studentIDs` is an encoded list a predicate can't read).
    static func lessonsSincePredicate(cutoff: Date) -> NSPredicate {
        let day = sinceDay(cutoff) as NSDate
        return NSPredicate(
            format: "presentedAt >= %@ OR (presentedAt == nil AND stateRaw == %@ AND createdAt >= %@)",
            day, LessonAssignmentState.presented.rawValue, day
        )
    }
}
