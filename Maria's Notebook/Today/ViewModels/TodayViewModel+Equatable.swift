// TodayViewModel+Equatable.swift
// What counts as "Today has not changed", so SwiftUI can skip a redraw.
//
// Split out of TodayViewModel.swift to keep that file under the line limit;
// the rules themselves are unchanged.

import Foundation

// MARK: - Equatable Conformance

extension TodayViewModel: Equatable {
    /// Compare only properties that affect UI rendering
    /// This allows SwiftUI to skip re-rendering when nothing visual has changed
    ///
    /// FUTURE OPTIMIZATION: For even more granular control, individual view sections
    /// could use `withObservationTracking` to track only specific properties they access.
    /// This would enable per-section updates instead of whole-view updates.
    /// Example:
    /// ```swift
    /// withObservationTracking {
    ///     ForEach(viewModel.todaysLessons) { lesson in
    ///         LessonRow(lesson: lesson)
    ///     }
    /// } onChange: {
    ///     // View updates only when todaysLessons changes, not when reminders change
    /// }
    /// ```
    static func == (lhs: TodayViewModel, rhs: TodayViewModel) -> Bool {
        lhs.inputsMatch(rhs)
            && lhs.listIDsMatch(rhs)
            && lhs.listCountsMatch(rhs)
            && lhs.followUpIDsMatch(rhs)
            && lhs.attendanceMatches(rhs)
        // Cache internals (studentsByID, lessonsByID, workByID, etc.) are intentionally
        // not compared — they don't directly affect rendering.
    }

    /// Inputs that trigger reloads.
    private func inputsMatch(_ other: TodayViewModel) -> Bool {
        date == other.date && levelFilter == other.levelFilter
    }

    /// Identity comparison of the rendered collections (count + element ids).
    private func listIDsMatch(_ other: TodayViewModel) -> Bool {
        let lessonsMatch: Bool = todaysLessons.count == other.todaysLessons.count
            && todaysLessons.map(\.id) == other.todaysLessons.map(\.id)
        let workMatch: Bool = completedWork.count == other.completedWork.count
            && completedWork.map(\.id) == other.completedWork.map(\.id)
        let remindersMatch: Bool = todaysReminders.count == other.todaysReminders.count
            && todaysReminders.map(\.id) == other.todaysReminders.map(\.id)
        let calendarMatch: Bool = todaysCalendarEvents.count == other.todaysCalendarEvents.count
            && todaysCalendarEvents.map(\.id) == other.todaysCalendarEvents.map(\.id)
        return lessonsMatch && workMatch && remindersMatch
            && calendarMatch && meetingAndNoteIDsMatch(other)
    }

    /// The rest of the id comparison, split off so neither half crosses the
    /// 100 ms type-check budget.
    private func meetingAndNoteIDsMatch(_ other: TodayViewModel) -> Bool {
        let meetingsMatch: Bool = scheduledMeetings.count == other.scheduledMeetings.count
            && scheduledMeetings.map(\.id) == other.scheduledMeetings.map(\.id)
            && completedMeetings.count == other.completedMeetings.count
            && completedMeetings.map(\.id) == other.completedMeetings.map(\.id)
        let notesMatch: Bool = recentNotes.count == other.recentNotes.count
            && recentNotes.map(\.id) == other.recentNotes.map(\.id)
        // The ready queue's id is child + next lesson, so a changed queue is a
        // changed list of ids — no deeper comparison is needed.
        let readyMatch: Bool = readyForNext.count == other.readyForNext.count
            && readyForNext.map(\.id) == other.readyForNext.map(\.id)
        return meetingsMatch && notesMatch && readyMatch
    }

    /// Counts of the remaining rendered collections.
    private func listCountsMatch(_ other: TodayViewModel) -> Bool {
        overdueSchedule.count == other.overdueSchedule.count
            && todaysSchedule.count == other.todaysSchedule.count
            && staleFollowUps.count == other.staleFollowUps.count
            && overdueReminders.count == other.overdueReminders.count
            && anytimeReminders.count == other.anytimeReminders.count
    }

    /// The due check-in rows: a row's id is its check-in, so completing one
    /// changes the id list; rescheduling keeps the id and moves the day, so
    /// the days are compared too. Its own function — the others sit near the
    /// type-check budget.
    private func followUpIDsMatch(_ other: TodayViewModel) -> Bool {
        followUpCheckIns.count == other.followUpCheckIns.count
            && followUpCheckIns.map(\.id) == other.followUpCheckIns.map(\.id)
            && followUpCheckIns.map(\.dueDay) == other.followUpCheckIns.map(\.dueDay)
    }

    /// Attendance summary affecting the header.
    private func attendanceMatches(_ other: TodayViewModel) -> Bool {
        attendanceSummary == other.attendanceSummary
            && absentToday == other.absentToday
            && leftEarlyToday == other.leftEarlyToday
    }
}
