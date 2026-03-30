import Foundation
import SwiftData

/// Centralized registry of all entity types that need to be backed up and restored.
/// This serves as the single source of truth to avoid hardcoding entity lists in multiple places.
struct BackupEntityRegistry {
    /// All entity types that should be included in backups.
    /// This must stay in sync with AppSchema — every user-data model should appear here.
    static let allTypes: [any PersistentModel.Type] = [
        // Core
        Student.self,
        Lesson.self,
        LessonAttachment.self,
        LessonAssignment.self,
        LessonPresentation.self,
        Note.self,
        NoteStudentLink.self,
        // Calendar
        NonSchoolDay.self,
        SchoolDayOverride.self,
        // Meetings
        StudentMeeting.self,
        MeetingTemplate.self,
        // Community
        CommunityTopic.self,
        ProposedSolution.self,
        CommunityAttachment.self,
        // Attendance
        AttendanceRecord.self,
        // Work tracking
        WorkModel.self,
        WorkCompletionRecord.self,
        WorkCheckIn.self,
        WorkParticipantEntity.self,
        WorkStep.self,
        SampleWork.self,
        SampleWorkStep.self,
        PracticeSession.self,
        // Projects
        Project.self,
        ProjectAssignmentTemplate.self,
        ProjectSession.self,
        ProjectRole.self,
        ProjectTemplateWeek.self,
        ProjectWeekRoleAssignment.self,
        // Issues
        Issue.self,
        IssueAction.self,
        // Tracks
        Track.self,
        TrackStep.self,
        StudentTrackEnrollment.self,
        GroupTrack.self,
        // Templates
        NoteTemplate.self,
        // Reminders & Calendar events
        Reminder.self,
        CalendarEvent.self,
        // Documents (metadata only)
        Document.self,
        // Supplies
        Supply.self,
        SupplyTransaction.self,
        // Procedures
        Procedure.self,
        // Schedules
        Schedule.self,
        ScheduleSlot.self,
        // Development
        DevelopmentSnapshot.self,
        // Todos
        TodoItem.self,
        TodoSubtask.self,
        TodoTemplate.self,
        // Agenda
        TodayAgendaOrder.self,
        // Planning recommendations
        PlanningRecommendation.self,
        // Resources
        Resource.self,
        // Going Out
        GoingOut.self,
        GoingOutChecklistItem.self,
        // Classroom Jobs
        ClassroomJob.self,
        JobAssignment.self,
        // Transition Plans
        TransitionPlan.self,
        TransitionChecklistItem.self,
        // Calendar Notes
        CalendarNote.self,
        // Scheduled Meetings
        ScheduledMeeting.self,
        // Album UI State
        AlbumGroupOrder.self,
        AlbumGroupUIState.self
    ]
    
    /// Entity type names for progress reporting and error messages
    static func entityName(for type: any PersistentModel.Type) -> String {
        String(describing: type)
    }
}

/// Structured progress tracking for backup operations
struct BackupProgress {
    enum Phase: Double {
        case collecting = 0.0
        case encoding = 0.30
        case encrypting = 0.50
        case writing = 0.70
        case verifying = 0.90
        case complete = 1.0
    }
    
    /// Calculate progress percentage for a phase with optional sub-progress within that phase
    static func progress(for phase: Phase, subProgress: Double = 0.0) -> Double {
        let phaseStart = phase.rawValue
        let phaseEnd: Double
        switch phase {
        case .collecting: phaseEnd = Phase.encoding.rawValue
        case .encoding: phaseEnd = Phase.encrypting.rawValue
        case .encrypting: phaseEnd = Phase.writing.rawValue
        case .writing: phaseEnd = Phase.verifying.rawValue
        case .verifying: phaseEnd = Phase.complete.rawValue
        case .complete: return 1.0
        }
        let phaseRange = phaseEnd - phaseStart
        return phaseStart + (phaseRange * subProgress)
    }
}
