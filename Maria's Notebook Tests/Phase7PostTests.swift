import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@Suite("Phase 7 Post-Tests: Backup v13 + ClassroomMembership")
@MainActor
final class Phase7PostTests {

    // MARK: - Format Version Bumped

    @Test("Backup format version is now 13")
    func backupFormatVersionIs13() {
        #expect(BackupFile.formatVersion == 13)
    }

    // MARK: - Entity Registry Updated

    @Test("BackupEntityRegistry contains exactly 62 entity types")
    func backupEntityRegistryCountIs62() {
        #expect(BackupEntityRegistry.allTypes.count == 62)
    }

    @Test("ClassroomMembership IS now in BackupEntityRegistry")
    func classroomMembershipInRegistry() {
        let containsMembership = BackupEntityRegistry.allTypes.contains(where: {
            $0 == CDClassroomMembership.self
        })
        #expect(containsMembership)
    }

    // MARK: - DTO Structure

    @Test("ClassroomMembershipDTO encodes and decodes correctly")
    func classroomMembershipDTORoundTrip() throws {
        let now = Date()
        let dto = ClassroomMembershipDTO(
            id: UUID(),
            classroomZoneID: "zone-abc-123",
            roleRaw: "leadGuide",
            ownerIdentity: "owner-identity-xyz",
            joinedAt: now,
            modifiedAt: now
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(dto)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ClassroomMembershipDTO.self, from: data)

        #expect(decoded.id == dto.id)
        #expect(decoded.classroomZoneID == dto.classroomZoneID)
        #expect(decoded.roleRaw == dto.roleRaw)
        #expect(decoded.ownerIdentity == dto.ownerIdentity)
    }

    // MARK: - BackupPayload has classroomMemberships field

    @Test("BackupPayload has classroomMemberships field (format v13)")
    func payloadHasV13Fields() {
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
        // v13 field should be nil (optional array) when not populated
        #expect(payload.classroomMemberships == nil)
        // v12 fields still nil too
        #expect(payload.classroomJobs == nil)
        #expect(payload.calendarNotes == nil)
    }

    // MARK: - v12 Backward Compatibility

    @Test("v12 backup payload without classroomMemberships decodes gracefully")
    func v12PayloadDecodesWithoutMemberships() throws {
        // Simulate a minimal v12 payload JSON (no classroomMemberships key)
        let json = """
        {
            "items": [],
            "students": [],
            "lessons": [],
            "lessonAssignments": [],
            "notes": [],
            "nonSchoolDays": [],
            "schoolDayOverrides": [],
            "studentMeetings": [],
            "communityTopics": [],
            "proposedSolutions": [],
            "communityAttachments": [],
            "attendance": [],
            "workCompletions": [],
            "projects": [],
            "projectAssignmentTemplates": [],
            "projectSessions": [],
            "projectRoles": [],
            "projectTemplateWeeks": [],
            "projectWeekRoleAssignments": [],
            "preferences": { "values": {} }
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)

        // classroomMemberships should be nil since it wasn't in the JSON
        #expect(payload.classroomMemberships == nil)
        // Other v12 optional fields also nil
        #expect(payload.goingOuts == nil)
    }

    // MARK: - v13 Payload with ClassroomMemberships

    @Test("v13 backup payload with classroomMemberships decodes correctly")
    func v13PayloadDecodesWithMemberships() throws {
        let json = """
        {
            "items": [],
            "students": [],
            "lessons": [],
            "lessonAssignments": [],
            "notes": [],
            "nonSchoolDays": [],
            "schoolDayOverrides": [],
            "studentMeetings": [],
            "communityTopics": [],
            "proposedSolutions": [],
            "communityAttachments": [],
            "attendance": [],
            "workCompletions": [],
            "projects": [],
            "projectAssignmentTemplates": [],
            "projectSessions": [],
            "projectRoles": [],
            "projectTemplateWeeks": [],
            "projectWeekRoleAssignments": [],
            "classroomMemberships": [
                {
                    "id": "550e8400-e29b-41d4-a716-446655440000",
                    "classroomZoneID": "zone-test-123",
                    "roleRaw": "assistant",
                    "ownerIdentity": "owner-test-456",
                    "joinedAt": "2026-01-15T10:30:00Z",
                    "modifiedAt": "2026-03-20T14:00:00Z"
                }
            ],
            "preferences": { "values": {} }
        }
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: data)

        #expect(payload.classroomMemberships?.count == 1)
        let membership = try #require(payload.classroomMemberships?.first)
        #expect(membership.classroomZoneID == "zone-test-123")
        #expect(membership.roleRaw == "assistant")
        #expect(membership.ownerIdentity == "owner-test-456")
        #expect(membership.id == UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000"))
    }

    // MARK: - All previous entity types still in registry

    @Test("Key shared store entity types still in registry after v13 bump")
    func sharedStoreEntitiesStillInRegistry() {
        let types = BackupEntityRegistry.allTypes
        #expect(types.contains(where: { $0 == CDStudent.self }))
        #expect(types.contains(where: { $0 == CDLesson.self }))
        #expect(types.contains(where: { $0 == CDTrackEntity.self }))
        #expect(types.contains(where: { $0 == CDSchedule.self }))
        #expect(types.contains(where: { $0 == CDProcedure.self }))
        #expect(types.contains(where: { $0 == CDClassroomJob.self }))
        #expect(types.contains(where: { $0 == CDGoingOut.self }))
        #expect(types.contains(where: { $0 == AlbumGroupOrder.self }))
    }

    @Test("Key private store entity types still in registry after v13 bump")
    func privateStoreEntitiesStillInRegistry() {
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
}
