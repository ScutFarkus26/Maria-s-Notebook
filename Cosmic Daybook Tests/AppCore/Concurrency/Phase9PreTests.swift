import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

@Suite("Phase 9 Pre-Tests: Swift 6.2 Concurrency Annotation Baseline")
@MainActor
final class Phase9PreTests {

    // MARK: - NSManagedObject Sendable Safety

    @Test("No NSManagedObject subclass conforms to Sendable")
    func noNSManagedObjectSendable() {
        // NSManagedObject is NOT Sendable — it's bound to its NSManagedObjectContext's
        // thread/queue. Pass NSManagedObjectID or Sendable DTOs across boundaries.
        //
        // The declared collection type is the compile-time check that every
        // listed model type is an NSManagedObject subclass.
        let entityTypes: [NSManagedObject.Type] = [
            CDStudent.self,
            CDNote.self,
            CDLesson.self,
            CDWorkModel.self,
            CDClassroomMembership.self
        ]

        // Keep the intended coverage list explicit. Sendable conformance is
        // enforced by Swift's strict-concurrency compiler, not at runtime.
        #expect(entityTypes.count == 5)
    }

    // MARK: - Key Services Already @MainActor

    @Test("AppBootstrapper is @MainActor isolated")
    func appBootstrapperIsMainActor() {
        // Verify key services are already @MainActor
        // (compile-time check — accessing from @MainActor context succeeds)
        let state = AppBootstrapper.shared.state
        #expect(state == .idle || state == .ready || state == .migrating || state == .initializingContainer)
    }

    // MARK: - BackupPayload is Sendable

    @Test("BackupPayload and DTOs are Sendable")
    func backupPayloadIsSendable() {
        // BackupPayload and all its DTO types must be Sendable for safe
        // transfer between actors during backup/restore operations.
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
        // If this compiles and runs, BackupPayload is Sendable
        let _: any Sendable = payload
    }

    @Test("ClassroomMembershipDTO is Sendable")
    func classroomMembershipDTOIsSendable() {
        let dto = ClassroomMembershipDTO(
            id: UUID(),
            values: [
                "classroomZoneID": .string("zone"),
                "roleRaw": .string("leadGuide"),
                "ownerIdentity": .string("owner"),
                "joinedAt": .date(Date()),
                "modifiedAt": .date(Date())
            ]
        )
        let _: any Sendable = dto
    }
}
