import Foundation
import CoreData
#if canImport(Testing)
import Testing
#endif

#if canImport(Testing)
@available(macOS 14, iOS 17, *)
@Suite("Phase 7 Pre-Tests: Backup System Baseline")
@MainActor
final class Phase7PreTests {

    // MARK: - Format Version Baseline

    @Test("Current backup format version is 12")
    func backupFormatVersionIs12() {
        #expect(BackupFile.formatVersion == 12)
    }

    // MARK: - Entity Registry Baseline

    @Test("BackupEntityRegistry contains exactly 57 entity types")
    func backupEntityRegistryCountMatches() {
        #expect(BackupEntityRegistry.allTypes.count == 57)
    }

    @Test("ClassroomMembership is NOT yet in BackupEntityRegistry")
    func classroomMembershipNotInRegistry() {
        let typeNames = BackupEntityRegistry.allTypes.map { String(describing: $0) }
        #expect(!typeNames.contains("CDClassroomMembership"))
    }

    // MARK: - Entity Coverage Cross-Checks

    @Test("All shared store entity types appear in registry")
    func sharedStoreEntitiesInRegistry() {
        let registryNames = Set(BackupEntityRegistry.allTypes.map {
            String(describing: $0)
        })

        // Shared entities that should be in backup (excluding ClassroomMembership which isn't added yet)
        let expectedSharedTypes: [String] = [
            "CDStudent", "CDLesson", "LessonAttachment", "CDLessonAssignment",
            "CDLessonPresentation", "CDNonSchoolDay", "CDSchoolDayOverride",
            "CDStudentMeeting", "CDMeetingTemplate",
            "CDCommunityTopicEntity", "ProposedSolution", "CommunityAttachment",
            "CDSampleWork", "CDSampleWorkStep",
            "CDTrackEntity", "TrackStep", "CDStudentTrackEnrollmentEntity", "CDGroupTrack",
            "CDNoteTemplate", "CDProcedure",
            "CDSchedule", "CDScheduleSlot",
            "CDResource",
            "CDGoingOut", "GoingOutChecklistItem",
            "CDClassroomJob", "CDJobAssignment",
            "CDTransitionPlan", "TransitionChecklistItem",
            "CDScheduledMeeting",
            "AlbumGroupOrder", "AlbumGroupUIState"
        ]

        for typeName in expectedSharedTypes {
            #expect(registryNames.contains(typeName), "Missing shared entity: \(typeName)")
        }
    }

    @Test("All private store entity types appear in registry")
    func privateStoreEntitiesInRegistry() {
        let registryNames = Set(BackupEntityRegistry.allTypes.map {
            String(describing: $0)
        })

        let expectedPrivateTypes: [String] = [
            "CDNote", "CDNoteStudentLink",
            "CDAttendanceRecord",
            "CDWorkModel", "CDWorkCompletionRecord", "CDWorkCheckIn",
            "WorkParticipantEntity", "CDWorkStep", "CDPracticeSession",
            "CDProject", "ProjectAssignmentTemplate", "CDProjectSession",
            "ProjectRole", "ProjectTemplateWeek", "ProjectWeekRoleAssignment",
            "CDIssue", "IssueAction",
            "CDReminder", "CDCalendarEvent",
            "CDDocument",
            "CDSupply", "SupplyTransaction",
            "DevelopmentSnapshot",
            "CDTodoItem", "CDTodoSubtask", "CDTodoTemplate",
            "CDTodayAgendaOrder",
            "PlanningRecommendation",
            "CDCalendarNote"
        ]

        for typeName in expectedPrivateTypes {
            #expect(registryNames.contains(typeName), "Missing private entity: \(typeName)")
        }
    }

    // MARK: - Export/Import Baseline

    @Test("Backup export produces non-empty data with seeded entities")
    func backupExportProducesValidData() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext

        CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Backup", lastName: "Test")
        CoreDataTestHelpers.seedNote(in: ctx, body: "Backup test note")
        CoreDataTestHelpers.save(ctx)

        let service = BackupService()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7_pre_test_\(UUID().uuidString).mtbbackup")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        let summary = try await service.exportBackup(
            viewContext: ctx,
            to: tempURL,
            password: nil,
            progress: { _, _ in }
        )

        #expect(summary.formatVersion == 12)
        #expect(FileManager.default.fileExists(atPath: tempURL.path))

        let fileSize = try FileManager.default.attributesOfItem(atPath: tempURL.path)[.size] as? Int ?? 0
        #expect(fileSize > 0, "Backup file should not be empty")
    }

    @Test("Backup round-trip: export then import restores entities")
    func backupImportRestoresEntities() async throws {
        let stack1 = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx1 = stack1.viewContext

        // Seed data
        CoreDataTestHelpers.seedStudent(in: ctx1, firstName: "RoundTrip", lastName: "Student")
        CoreDataTestHelpers.seedNote(in: ctx1, body: "RoundTrip note")
        CoreDataTestHelpers.save(ctx1)

        // Export
        let service = BackupService()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("phase7_roundtrip_\(UUID().uuidString).mtbbackup")

        defer { try? FileManager.default.removeItem(at: tempURL) }

        _ = try await service.exportBackup(
            viewContext: ctx1,
            to: tempURL,
            password: nil,
            progress: { _, _ in }
        )

        // Import into fresh stack
        let stack2 = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx2 = stack2.viewContext

        _ = try await service.importBackup(
            viewContext: ctx2,
            from: tempURL,
            mode: .replace,
            password: nil,
            progress: { _, _ in }
        )

        // Verify entities restored
        let studentRequest: NSFetchRequest<CDStudent> = NSFetchRequest(entityName: "Student")
        let students = ctx2.safeFetch(studentRequest)
        #expect(students.count >= 1, "Should have at least 1 student after import")

        let noteRequest: NSFetchRequest<CDNote> = NSFetchRequest(entityName: "Note")
        let notes = ctx2.safeFetch(noteRequest)
        #expect(notes.count >= 1, "Should have at least 1 note after import")
    }
}
#endif
