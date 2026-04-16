import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@Suite("Phase 7 Pre-Tests: Backup System Baseline")
@MainActor
final class Phase7PreTests {

    // MARK: - Format Version Baseline

    @Test("Current backup format version is 12")
    func backupFormatVersionIs12() {
        #expect(BackupFile.formatVersion == 12)
    }

    // MARK: - Entity Registry Baseline

    @Test("BackupEntityRegistry contains exactly 61 entity types")
    func backupEntityRegistryCountMatches() {
        #expect(BackupEntityRegistry.allTypes.count == 61)
    }

    @Test("ClassroomMembership is NOT yet in BackupEntityRegistry")
    func classroomMembershipNotInRegistry() {
        let containsMembership = BackupEntityRegistry.allTypes.contains(where: {
            $0 == CDClassroomMembership.self
        })
        #expect(!containsMembership)
    }

    // MARK: - Registry completeness (type identity check, not string names)

    @Test("Key shared store entity types are in the registry")
    func sharedStoreEntitiesInRegistry() {
        let types = BackupEntityRegistry.allTypes
        #expect(types.contains(where: { $0 == CDStudent.self }))
        #expect(types.contains(where: { $0 == CDLesson.self }))
        #expect(types.contains(where: { $0 == CDTrackEntity.self }))
        #expect(types.contains(where: { $0 == CDSchedule.self }))
        #expect(types.contains(where: { $0 == CDProcedure.self }))
        #expect(types.contains(where: { $0 == CDClassroomJob.self }))
        #expect(types.contains(where: { $0 == CDGoingOut.self }))
    }

    @Test("Key private store entity types are in the registry")
    func privateStoreEntitiesInRegistry() {
        let types = BackupEntityRegistry.allTypes
        #expect(types.contains(where: { $0 == CDNote.self }))
        #expect(types.contains(where: { $0 == CDAttendanceRecord.self }))
        #expect(types.contains(where: { $0 == CDWorkModel.self }))
        #expect(types.contains(where: { $0 == CDTodoItem.self }))
        #expect(types.contains(where: { $0 == CDProject.self }))
        #expect(types.contains(where: { $0 == CDIssue.self }))
        #expect(types.contains(where: { $0 == CDReminder.self }))
        #expect(types.contains(where: { $0 == CDCalendarNote.self }))
    }

    // MARK: - Backup Payload Structure

    @Test("BackupPayload has classroomJobs field (format v12)")
    func payloadHasV12Fields() {
        // Verify v12 payload fields exist (compile-time check + runtime)
        let payload = BackupPayload(
            items: [], students: [], lessons: [],
            lessonAssignments: [], notes: [], nonSchoolDays: [],
            schoolDayOverrides: [], studentMeetings: [],
            communityTopics: [], proposedSolutions: [],
            communityAttachments: [], attendance: [],
            workCompletions: [], projects: [],
            projectAssignmentTemplates: [], projectSessions: [],
            projectRoles: [], projectTemplateWeeks: [],
            projectWeekRoleAssignments: [],
            preferences: PreferencesDTO(values: [:])
        )
        // v12 fields should be nil (optional arrays)
        #expect(payload.classroomJobs == nil)
        #expect(payload.calendarNotes == nil)
        #expect(payload.scheduledMeetings == nil)
    }
}
