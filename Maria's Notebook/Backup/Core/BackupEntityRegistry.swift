import Foundation
import CoreData

/// Centralized registry of all entity types that need to be backed up and restored.
/// This serves as the single source of truth to avoid hardcoding entity lists in multiple places.
struct BackupEntityRegistry {
    /// All entity types that should be included in backups.
    /// This must stay in sync with AppSchema — every user-data model should appear here.
    static let allTypes: [NSManagedObject.Type] = [
        // Core
        CDStudent.self,
        CDLesson.self,
        LessonAttachment.self,
        CDLessonAssignment.self,
        CDLessonPresentation.self,
        CDNote.self,
        CDNoteStudentLink.self,
        // Calendar
        CDNonSchoolDay.self,
        CDSchoolDayOverride.self,
        // Meetings
        CDStudentMeeting.self,
        CDMeetingTemplate.self,
        // Community
        CDCommunityTopicEntity.self,
        ProposedSolution.self,
        CommunityAttachment.self,
        // Attendance
        CDAttendanceRecord.self,
        // Work tracking
        CDWorkModel.self,
        CDWorkCompletionRecord.self,
        CDWorkCheckIn.self,
        WorkParticipantEntity.self,
        CDWorkStep.self,
        CDSampleWork.self,
        CDSampleWorkStep.self,
        CDPracticeSession.self,
        // Projects
        CDProject.self,
        ProjectAssignmentTemplate.self,
        CDProjectSession.self,
        ProjectRole.self,
        ProjectTemplateWeek.self,
        ProjectWeekRoleAssignment.self,
        // Issues
        CDIssue.self,
        IssueAction.self,
        // Tracks
        CDTrackEntity.self,
        TrackStep.self,
        CDStudentTrackEnrollmentEntity.self,
        CDGroupTrack.self,
        // Templates
        CDNoteTemplate.self,
        // Reminders & Calendar events
        CDReminder.self,
        CDCalendarEvent.self,
        // Documents (metadata only)
        CDDocument.self,
        // Supplies
        CDSupply.self,
        SupplyTransaction.self,
        // Procedures
        CDProcedure.self,
        // Schedules
        CDSchedule.self,
        CDScheduleSlot.self,
        // Development
        DevelopmentSnapshot.self,
        // Todos
        CDTodoItem.self,
        CDTodoSubtask.self,
        CDTodoTemplate.self,
        // Agenda
        CDTodayAgendaOrder.self,
        // Planning recommendations
        PlanningRecommendation.self,
        // Resources
        CDResource.self,
        // Going Out
        CDGoingOut.self,
        GoingOutChecklistItem.self,
        // Classroom Jobs
        CDClassroomJob.self,
        CDJobAssignment.self,
        // Transition Plans
        CDTransitionPlan.self,
        TransitionChecklistItem.self,
        // Calendar Notes
        CDCalendarNote.self,
        // Scheduled Meetings
        CDScheduledMeeting.self,
        // Album UI State
        AlbumGroupOrder.self,
        AlbumGroupUIState.self
    ]
    
    /// Entity type names for progress reporting and error messages
    static func entityName(for type: NSManagedObject.Type) -> String {
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
