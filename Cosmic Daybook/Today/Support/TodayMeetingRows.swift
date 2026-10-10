// TodayMeetingRows.swift
// The day's meetings under the level filter, and the names their rows show.
//
// Lessons, work and attendance on Today follow the level filter; meetings
// didn't, so "Upper" still listed every Lower child's meeting. And a row's name
// came from the enrolled cache, whose miss reads "Student", so a meeting for a
// child who has left read "Student" and "Student removed" never showed.

import Foundation

enum TodayMeetingRows {

    /// Scheduled meetings for the level filter: under a level, those naming a
    /// child of that level (by the enrolled cache); under All, every meeting, so
    /// one for a child who has left can still be seen and removed.
    static func filter(
        _ meetings: [CDScheduledMeeting], studentsByID: [UUID: CDStudent], levelFilter: LevelFilter
    ) -> [CDScheduledMeeting] {
        guard levelFilter != .all else { return meetings }
        return meetings.filter { meeting in
            meeting.allStudentIDs.compactMap(UUID.init(uuidString:)).contains { id in
                studentsByID[id].map { levelFilter.matches($0.level) } ?? false
            }
        }
    }

    /// Completed meetings for the level filter, by the same rule.
    static func filterCompleted(
        _ meetings: [CDStudentMeeting], studentsByID: [UUID: CDStudent], levelFilter: LevelFilter
    ) -> [CDStudentMeeting] {
        guard levelFilter != .all else { return meetings }
        return meetings.filter { meeting in
            meeting.studentIDUUID.flatMap { studentsByID[$0] }.map { levelFilter.matches($0.level) } ?? false
        }
    }

    /// The row's names ("Maya S, Etty D + 2 more"), from every child Today knows
    /// of, enrolled or not; "Student removed" when none of them is still in the
    /// notebook.
    static func names(for ids: [UUID], knownStudents: [UUID: CDStudent]) -> String {
        let names = ids.compactMap { knownStudents[$0]?.shortName }.filter { !$0.isEmpty }
        guard !names.isEmpty else { return "Student removed" }
        if names.count <= 2 {
            return names.joined(separator: ", ")
        }
        return "\(names[0]), \(names[1]) + \(names.count - 2) more"
    }
}
