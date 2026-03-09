import SwiftData

/// Centralized SwiftData schema for the app. Keep this list as the single source of truth.
/// Both the production ModelContainer and the preview container should reference this schema
/// to avoid drift between builds and previews.
struct AppSchema {
    static let schema = Schema([
        Student.self,
        Lesson.self,
        LessonAttachment.self,
        // Legacy model removed — fully migrated to LessonAssignment
        WorkCompletionRecord.self,
        WorkModel.self,
        WorkCheckIn.self,
        WorkParticipantEntity.self,
        WorkStep.self,
        SampleWork.self,
        SampleWorkStep.self,
        PracticeSession.self,
        AttendanceRecord.self,
        NonSchoolDay.self,
        SchoolDayOverride.self,
        Note.self,
        NoteStudentLink.self,
        NoteTemplate.self,
        MeetingTemplate.self,
        CommunityTopic.self,
        ProposedSolution.self,
        CommunityAttachment.self,
        LessonPresentation.self,
        LessonAssignment.self,  // Entity name must match stored data; Presentation is a typealias
        // Legacy check-in system removed - now using WorkCheckIn
        StudentMeeting.self,
        ScheduledMeeting.self,
        Project.self,
        ProjectAssignmentTemplate.self,
        ProjectSession.self,
        ProjectRole.self,
        ProjectTemplateWeek.self,
        ProjectWeekRoleAssignment.self,
        Reminder.self,
        CalendarEvent.self,
        Track.self,
        TrackStep.self,
        StudentTrackEnrollment.self,
        GroupTrack.self,
        Document.self,
        Supply.self,
        SupplyTransaction.self,
        Procedure.self,
        Schedule.self,
        ScheduleSlot.self,
        Issue.self,
        IssueAction.self,
        DevelopmentSnapshot.self,
        TodoItem.self,
        TodoSubtask.self,
        TodoTemplate.self,
        TodayAgendaOrder.self,
        PlanningRecommendation.self,
        Resource.self
    ])
}
