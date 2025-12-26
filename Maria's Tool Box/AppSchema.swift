import SwiftData

/// Centralized SwiftData schema for the app. Keep this list as the single source of truth.
/// Both the production ModelContainer and the preview container should reference this schema
/// to avoid drift between builds and previews.
struct AppSchema {
    static let schema = Schema([
        Item.self,
        Student.self,
        Lesson.self,
        StudentLesson.self,
        WorkModel.self,
        WorkNote.self,
        WorkParticipantEntity.self,
        WorkCompletionRecord.self,
        AttendanceRecord.self,
        WorkCheckIn.self,
        NonSchoolDay.self,
        SchoolDayOverride.self,
        ScopedNote.self,
        Note.self,
        CommunityTopic.self,
        ProposedSolution.self,
        MeetingNote.self,
        CommunityAttachment.self,
        Presentation.self,
        WorkContract.self,
        WorkPlanItem.self,
        StudentMeeting.self,
        BookClub.self,
        BookClubAssignmentTemplate.self,
        BookClubSession.self,
        // BookClubDeliverable.self removed
        BookClubRole.self,
        BookClubTemplateWeek.self,
        BookClubWeekRoleAssignment.self,
        BookClubChoiceSet.self,
        BookClubChoiceItem.self,
    ])
}
