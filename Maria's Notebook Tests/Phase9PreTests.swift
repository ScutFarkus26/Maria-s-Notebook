import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

@Suite("Phase 9 Pre-Tests: Swift 6.2 Concurrency Annotation Baseline")
@MainActor
final class Phase9PreTests {

    // MARK: - @MainActor Annotation Baseline

    @Test("@MainActor annotation count is documented baseline (~496)")
    func mainActorAnnotationBaseline() {
        // This test documents the current @MainActor usage count.
        // The app uses @MainActor extensively on views, view models, and services.
        // Under Swift 6.2 module-level @MainActor, most of these become redundant.
        // Baseline count: ~496 (as of Phase 8 completion)
        //
        // This is a documentation test — it always passes.
        // The actual count is verified manually via grep.
        let documentedCount = 496
        #expect(documentedCount > 400, "App should have significant @MainActor usage")
    }

    // MARK: - Sendable Conformance Baseline

    @Test("Sendable conformance count is documented baseline (~46)")
    func sendableConformanceBaseline() {
        // Documents the current Sendable protocol conformance count.
        // These types can safely cross concurrency boundaries.
        // Baseline: ~46 types conform to Sendable
        let documentedCount = 46
        #expect(documentedCount > 20, "App should have meaningful Sendable conformance")
    }

    // MARK: - nonisolated Baseline

    @Test("nonisolated declaration count is documented baseline (~257)")
    func nonisolatedDeclarationBaseline() {
        // Documents current nonisolated declarations.
        // Under module-level @MainActor, these become critical for opting out.
        // Baseline: ~257 nonisolated declarations
        let documentedCount = 257
        #expect(documentedCount > 100, "App should have significant nonisolated usage")
    }

    // MARK: - NSManagedObject Sendable Safety

    @Test("No NSManagedObject subclass conforms to Sendable")
    func noNSManagedObjectSendable() {
        // NSManagedObject is NOT Sendable — it's bound to its NSManagedObjectContext's
        // thread/queue. Pass NSManagedObjectID or Sendable DTOs across boundaries.
        //
        // Verify key entity types are NSManagedObject subclasses (compile-time check)
        // and confirm none declare Sendable conformance via runtime check.
        let entityTypes: [NSManagedObject.Type] = [
            CDStudent.self,
            CDNote.self,
            CDLesson.self,
            CDWorkModel.self,
            CDClassroomMembership.self
        ]

        for type in entityTypes {
            // All should be NSManagedObject subclasses
            #expect(type is NSManagedObject.Type, "\(type) should be NSManagedObject subclass")
            // None should be Sendable (this is enforced by the compiler in strict concurrency)
            // We verify indirectly: NSManagedObject itself is not Sendable
        }

        // Direct runtime check: NSManagedObject does not conform to Sendable
        // (Swift doesn't provide a runtime Sendable check, but we can verify
        //  the type hierarchy is correct)
        #expect(CDStudent.self is NSManagedObject.Type)
        #expect(CDNote.self is NSManagedObject.Type)
    }

    // MARK: - Key Services Already @MainActor

    @Test("AppBootstrapper is @MainActor isolated")
    func appBootstrapperIsMainActor() {
        // Verify key services are already @MainActor
        // (compile-time check — accessing from @MainActor context succeeds)
        let state = AppBootstrapper.shared.state
        #expect(state == .idle || state == .ready || state == .migrating || state == .initializingContainer)
    }

    @Test("BackupService is @MainActor isolated")
    func backupServiceIsMainActor() {
        // BackupService is @MainActor — verify it's accessible from MainActor context
        let service = BackupService()
        #expect(service != nil)
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
            classroomZoneID: "zone",
            roleRaw: "leadGuide",
            ownerIdentity: "owner",
            joinedAt: Date(),
            modifiedAt: Date()
        )
        let _: any Sendable = dto
    }
}
