import Foundation

/// User-understandable permission categories that group Core Data entities.
/// Lead guides toggle these categories to control what assistants can write.
enum SharingPermissionCategory: String, CaseIterable, Identifiable, Sendable {
    case attendance
    case notes
    case workCheckIns
    case workItems
    case presentations
    case studentMeetings
    case projects
    case todos
    case issues
    case practiceSessions
    case documents

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .attendance: return "Attendance"
        case .notes: return "Observations & Notes"
        case .workCheckIns: return "Work Check-ins"
        case .workItems: return "Work Items"
        case .presentations: return "Presentations"
        case .studentMeetings: return "Student Meetings"
        case .projects: return "Projects"
        case .todos: return "Todos"
        case .issues: return "Issues"
        case .practiceSessions: return "Practice Sessions"
        case .documents: return "Documents"
        }
    }

    var icon: String {
        switch self {
        case .attendance: return "checkmark.circle"
        case .notes: return "note.text"
        case .workCheckIns: return "clock.badge.checkmark"
        case .workItems: return "tray.full"
        case .presentations: return "person.2.wave.2"
        case .studentMeetings: return "person.bubble"
        case .projects: return "folder"
        case .todos: return "checklist"
        case .issues: return "exclamationmark.triangle"
        case .practiceSessions: return "figure.mind.and.body"
        case .documents: return "doc"
        }
    }

    /// Core Data entity names included in this category.
    var entityNames: [String] {
        switch self {
        case .attendance:
            return ["AttendanceRecord"]
        case .notes:
            return ["Note", "NoteStudentLink"]
        case .workCheckIns:
            return ["WorkCheckIn"]
        case .workItems:
            return ["WorkModel", "WorkStep", "WorkParticipantEntity", "WorkCompletionRecord"]
        case .presentations:
            return ["LessonAssignment"]
        case .studentMeetings:
            return ["StudentMeeting", "ScheduledMeeting"]
        case .projects:
            return [
                "Project", "ProjectSession", "ProjectRole",
                "ProjectAssignmentTemplate", "ProjectTemplateWeek", "ProjectWeekRoleAssignment"
            ]
        case .todos:
            return ["TodoItem", "TodoSubtask"]
        case .issues:
            return ["Issue", "IssueAction"]
        case .practiceSessions:
            return ["PracticeSession"]
        case .documents:
            return ["Document"]
        }
    }

    /// Categories enabled by default for assistants.
    static let defaultEnabled: Set<SharingPermissionCategory> = [
        .attendance, .notes, .workCheckIns
    ]
}
