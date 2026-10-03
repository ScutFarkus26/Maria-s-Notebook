// BackupPlainNames.swift
// What each backed-up type is called on screen: "Planned lessons", not
// "LessonAssignment". The restore preview, the restore summary and anything
// else that lists a backup's contents by type reads this one map.
//
// Keys are the type names with the Core Data dressing taken off ("CD" in
// front, "Entity" behind), so the archive's "WorkParticipantEntity", the
// preview's "WorkParticipant" and the class "CDWorkParticipantEntity" all
// find the same noun. `BackupPlainNamesTests` fails until every type in
// `BackupEntityTable` has one.

import Foundation

nonisolated enum BackupPlainNames {

    /// What a type with no entry here is called.
    static let fallback = "Other items"

    /// The plain plural noun for a backed-up type, or `fallback`.
    static func noun(for entityName: String) -> String {
        name(for: entityName) ?? fallback
    }

    /// The plain noun, or nil when the map has no entry for the type.
    static func name(for entityName: String) -> String? {
        nouns[normalized(entityName)]
    }

    /// "CDCommunityTopicEntity" → "CommunityTopic"; "WorkParticipantEntity" → "WorkParticipant".
    static func normalized(_ entityName: String) -> String {
        var name = entityName
        if name.hasPrefix("CD"), name.dropFirst(2).first?.isUppercase == true { name.removeFirst(2) }
        if name.hasSuffix("Entity"), name.count > "Entity".count { name.removeLast("Entity".count) }
        return name
    }

    private static let nouns: [String: String] = [
        // Students, lessons and notes
        "Student": "Students",
        "Lesson": "Lessons",
        "LessonAssignment": "Planned lessons",
        "LessonPresentation": "Lessons given",
        "LessonAttachment": "Lesson files",
        "LessonRecallCheck": "Recall checks",
        "LessonSequenceSettings": "Lesson sequence settings",
        "Note": "Notes",
        "NoteStudentLink": "Children named in notes",
        "NoteTemplate": "Note templates",
        "DevelopmentSnapshot": "Saved insights",
        "StudentMeeting": "Student meetings",
        "MeetingTemplate": "Meeting templates",
        "MeetingWorkReview": "Work looked at in meetings",
        "StudentFocusItem": "Meeting goals",
        "ScheduledMeeting": "Scheduled meetings",
        "Guardian": "Parents and guardians",
        "ParentCommunication": "Messages to parents",
        // Attendance and the calendar
        "AttendanceRecord": "Attendance",
        "AttendanceDayLock": "Locked attendance days",
        "AttendanceEmailSend": "Front-desk emails",
        "AttendanceEmailSettings": "Front-desk email settings",
        "NonSchoolDay": "Days off",
        "SchoolDayOverride": "Extra school days",
        "CalendarEvent": "Calendar events",
        "CalendarNote": "Calendar notes",
        "Reminder": "Reminders",
        "DayPad": "Day pads",
        "YearPlanEntry": "Year plan",
        // Work
        "WorkModel": "Work",
        "WorkCheckIn": "Work check-ins",
        "WorkStep": "Work steps",
        "WorkParticipant": "Children on work",
        "WorkCompletionRecord": "Completed work",
        "PracticeSession": "Practice sessions",
        "SampleWork": "Sample work",
        "SampleWorkStep": "Sample work steps",
        // Tracks
        "Track": "Tracks",
        "TrackStep": "Track steps",
        "StudentTrackEnrollment": "Children on tracks",
        "SequenceTrack": "Lesson sequences",
        // Community, projects and book club
        "CommunityTopic": "Community meeting topics",
        "ProposedSolution": "Proposed solutions",
        "CommunityAttachment": "Community meeting files",
        "Project": "Projects",
        "ProjectSession": "Project sessions",
        "ProjectRole": "Project roles",
        "ProjectAssignmentTemplate": "Old project plans",
        "ProjectTemplateWeek": "Old project plans",
        "ProjectWeekRoleAssignment": "Old project plans",
        "Story": "Stories",
        "BookClubPacket": "Book club packets",
        "BookClubSession": "Book clubs",
        "BookClubMeeting": "Book club meetings",
        // The classroom
        "Document": "Documents",
        "Supply": "Supplies",
        "SupplyTransaction": "Supply changes",
        "OrderItem": "Orders",
        "Procedure": "Procedures",
        "Schedule": "Schedules",
        "ScheduleSlot": "Schedule times",
        "Issue": "Issues",
        "IssueAction": "Issue follow-ups",
        "ClassroomJob": "Classroom jobs",
        "JobAssignment": "Job assignments",
        "GoingOut": "Going-outs",
        "GoingOutChecklistItem": "Going-out checklist items",
        "Resource": "Resources",
        "PlanningRecommendation": "Planning suggestions",
        "ClassroomMembership": "Classroom sharing setup",
        // Todos and Today
        "TodoItem": "Todos",
        "TodoSubtask": "Todo steps",
        "TodoTemplate": "Todo templates",
        "TodayAgendaOrder": "Today's order",
        // Albums
        "AlbumBookmark": "Album bookmarks",
        "AlbumPageNote": "Album page notes",
        "AlbumRecentVisit": "Recently read album pages",
        "AlbumReadingPosition": "Album reading places",
        "AlbumHighlight": "Album highlights",
        "AlbumPageInk": "Album drawings"
    ]

    /// Per-type counts gathered under their plain nouns, counts of types that
    /// share a noun added together (the three old project types, say).
    static func grouped(_ counts: [String: Int]) -> [String: Int] {
        counts.reduce(into: [:]) { result, entry in
            result[noun(for: entry.key), default: 0] += entry.value
        }
    }
}
