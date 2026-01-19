import SwiftData

/// Centralized SwiftData schema for the app. Keep this list as the single source of truth.
/// Both the production ModelContainer and the preview container should reference this schema
/// to avoid drift between builds and previews.
struct AppSchema {
    static let schema = Schema([
        Student.self,
        Lesson.self,
        StudentLesson.self,
        WorkCompletionRecord.self,
        WorkModel.self,
        WorkCheckIn.self,
        WorkParticipantEntity.self,
        WorkStep.self,
        AttendanceRecord.self,
        NonSchoolDay.self,
        SchoolDayOverride.self,
        Note.self,
        NoteStudentLink.self,
        NoteTemplate.self,
        CommunityTopic.self,
        ProposedSolution.self,
        CommunityAttachment.self,
        Presentation.self,
        LessonPresentation.self,
        WorkPlanItem.self,
        StudentMeeting.self,
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
    ])
}
