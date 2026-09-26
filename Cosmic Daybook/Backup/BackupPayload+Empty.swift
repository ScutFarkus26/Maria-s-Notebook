import Foundation

nonisolated extension BackupPayload {
    /// A payload with every always-present array empty and every later-format
    /// array `nil`: what the collector fills and the archive decoder assigns into.
    static func collecting(preferences: PreferencesDTO) -> BackupPayload {
        BackupPayload(
            items: [], students: [], lessons: [],
            lessonAssignments: [],
            notes: [], nonSchoolDays: [], schoolDayOverrides: [],
            studentMeetings: [], communityTopics: [],
            proposedSolutions: [], communityAttachments: [],
            attendance: [], workCompletions: [],
            projects: [], projectAssignmentTemplates: [],
            projectSessions: [], projectRoles: [],
            projectTemplateWeeks: [], projectWeekRoleAssignments: [],
            preferences: preferences
        )
    }
}
