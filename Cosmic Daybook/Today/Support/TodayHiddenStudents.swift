// TodayHiddenStudents.swift
// Hidden test students' meetings and notes, kept off Today.

import Foundation

/// The roster's hidden test students (Settings › Test Students) are filtered
/// out of Today's lessons, work and attendance, but their meetings and the
/// recent notes about them still showed (bug hunt 2026-11-03 #55). A record
/// about only hidden children leaves; one that also names a shown child, or
/// the whole class, stays.
enum TodayHiddenStudents {

    /// Scheduled meetings, less those booked for hidden children only.
    static func meetings(_ meetings: [CDScheduledMeeting], hiding hidden: Set<UUID>) -> [CDScheduledMeeting] {
        guard !hidden.isEmpty else { return meetings }
        return meetings.filter { !isOnlyAbout(hidden, $0.allStudentIDs.compactMap(UUID.init(uuidString:))) }
    }

    /// Completed meetings, less a hidden child's.
    static func completedMeetings(_ meetings: [CDStudentMeeting], hiding hidden: Set<UUID>) -> [CDStudentMeeting] {
        guard !hidden.isEmpty else { return meetings }
        return meetings.filter { meeting in
            meeting.studentIDUUID.map { !hidden.contains($0) } ?? true
        }
    }

    /// Notes, less those about hidden children only.
    static func notes(_ notes: [CDNote], hiding hidden: Set<UUID>) -> [CDNote] {
        guard !hidden.isEmpty else { return notes }
        return notes.filter { note in
            switch note.scope {
            case .all: return true
            case .student(let id): return !hidden.contains(id)
            case .students(let ids): return !isOnlyAbout(hidden, ids)
            }
        }
    }

    private static func isOnlyAbout(_ hidden: Set<UUID>, _ ids: [UUID]) -> Bool {
        !ids.isEmpty && ids.allSatisfy(hidden.contains)
    }
}
