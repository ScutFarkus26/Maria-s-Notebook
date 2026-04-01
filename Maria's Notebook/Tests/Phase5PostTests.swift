import Foundation
import CoreData
#if canImport(Testing)
import Testing
#endif

#if canImport(Testing)
@available(macOS 14, iOS 17, *)
@Suite("Phase 5 Post-Tests: Sharing Verification")
@MainActor
final class Phase5PostTests {

    // MARK: - ClassroomPermissions Matrix

    @Test("Lead guide can write all entities")
    func leadGuideFullWrite() {
        let allEntities = CoreDataStack.sharedEntityNames.union(CoreDataStack.privateEntityNames)
        for entity in allEntities {
            #expect(
                ClassroomPermissions.canWrite(entityName: entity, role: .leadGuide),
                "Lead guide should be able to write \(entity)"
            )
        }
    }

    @Test("Assistant can only write 4 specific entities")
    func assistantLimitedWrite() {
        let allowed: Set<String> = ["AttendanceRecord", "Note", "NoteStudentLink", "WorkCheckIn"]
        for entity in allowed {
            #expect(
                ClassroomPermissions.canWrite(entityName: entity, role: .assistant),
                "Assistant should be able to write \(entity)"
            )
        }
    }

    @Test("Assistant cannot write shared classroom entities")
    func assistantCannotWriteShared() {
        let denied = ["Student", "Lesson", "Track", "TrackStep", "Schedule", "Procedure"]
        for entity in denied {
            #expect(
                !ClassroomPermissions.canWrite(entityName: entity, role: .assistant),
                "Assistant should NOT be able to write \(entity)"
            )
        }
    }

    @Test("Only lead guide can manage sharing")
    func sharingManagement() {
        #expect(ClassroomPermissions.canManageSharing(role: .leadGuide))
        #expect(!ClassroomPermissions.canManageSharing(role: .assistant))
    }

    @Test("canDelete matches canWrite for both roles")
    func deleteMatchesWrite() {
        let entities = ["Student", "Note", "AttendanceRecord", "Lesson"]
        for entity in entities {
            for role in CDClassroomMembership.ClassroomRole.allCases {
                #expect(
                    ClassroomPermissions.canDelete(entityName: entity, role: role)
                        == ClassroomPermissions.canWrite(entityName: entity, role: role)
                )
            }
        }
    }

    // MARK: - ClassroomRepository CRUD

    @Test("ClassroomRepository CRUD round-trip")
    func repositoryCRUD() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let repo = ClassroomRepository(context: stack.viewContext)

        // Create
        let membership = repo.createMembership(
            classroomZoneID: "zone-test",
            role: .leadGuide,
            ownerIdentity: "owner-abc"
        )
        #expect(repo.save(reason: "test create"))

        // Fetch by ID
        let fetched = repo.fetchMembership(id: membership.id!)
        #expect(fetched != nil)
        #expect(fetched?.classroomZoneID == "zone-test")
        #expect(fetched?.role == .leadGuide)

        // Fetch current
        let current = repo.fetchCurrentMembership()
        #expect(current?.id == membership.id)

        // Update
        #expect(repo.updateRole(id: membership.id!, role: .assistant))
        let updated = repo.fetchMembership(id: membership.id!)
        #expect(updated?.role == .assistant)

        // Delete
        repo.deleteMembership(id: membership.id!)
        #expect(repo.save(reason: "test delete"))
        #expect(repo.fetchCurrentMembership() == nil)
    }

    // MARK: - Service Initialization

    @Test("ClassroomSharingService initializes from AppDependencies without crash")
    func serviceInit() throws {
        let deps = try CoreDataTestHelpers.makeDependencies()
        let service = deps.classroomSharingService
        #expect(service.currentRole == .leadGuide)
        #expect(!service.isSharing)
    }

    // MARK: - Settings Integration

    @Test("SettingsCategory.classroom has correct properties")
    func settingsCategoryClassroom() {
        let category = SettingsCategory.classroom
        #expect(category.displayName == "Classroom")
        #expect(category.icon == "person.2.badge.gearshape.fill")
        #expect(category.searchKeywords.contains("sharing"))
        #expect(!category.detailedSettings.isEmpty)
    }

    // MARK: - RepositoryContainer

    @Test("RepositoryContainer.classrooms returns valid repository")
    func repositoryContainerClassrooms() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let repos = RepositoryContainer(context: stack.viewContext, saveCoordinator: nil)
        let classroomRepo = repos.classrooms
        // Verify it can fetch without crashing
        let memberships = classroomRepo.fetchMemberships()
        #expect(memberships.isEmpty)
    }
}
#endif
