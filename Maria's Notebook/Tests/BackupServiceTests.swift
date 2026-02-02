import Foundation
import SwiftData
import CryptoKit
#if canImport(Testing)
import Testing
@testable import Maria_s_Notebook
#endif

#if canImport(Testing)
@Suite("BackupService basic tests", .serialized)
@MainActor
struct BackupServiceTests {

    // MARK: - Test Helpers

    /// Creates a container with all entity types needed for BackupService operations.
    /// BackupService.exportBackup and importBackup access all entity types, so we need a full schema.
    private func makeBackupTestContainer() throws -> ModelContainer {
        let schema = Schema([
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonAssignment.self,
            WorkModel.self,
            WorkPlanItem.self,
            WorkCompletionRecord.self,
            WorkCheckIn.self,
            WorkParticipantEntity.self,
            WorkStep.self,
            Note.self,
            NoteStudentLink.self,
            NonSchoolDay.self,
            SchoolDayOverride.self,
            StudentMeeting.self,
            LessonPresentation.self,
            CommunityTopic.self,
            ProposedSolution.self,
            CommunityAttachment.self,
            AttendanceRecord.self,
            Project.self,
            ProjectAssignmentTemplate.self,
            ProjectSession.self,
            ProjectRole.self,
            ProjectTemplateWeek.self,
            ProjectWeekRoleAssignment.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test("Export then import (replace) round-trips counts")
    func roundTripReplace() async throws {
        let container = try makeBackupTestContainer()
        let ctx = container.mainContext
        // Seed minimal data
        let s = Student(firstName: "A", lastName: "B", birthday: Date(), level: .lower)
        let l = Lesson(name: "L", subject: "S", group: "G", subheading: "", writeUp: "")
        ctx.insert(s); ctx.insert(l)
        try ctx.save()

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(BackupFile.fileExtension)
        let service = BackupService()
        try await service.exportBackup(modelContext: ctx, to: tmp, password: nil) { _, _ in }

        // Wipe and restore
        try await service.importBackup(modelContext: ctx, from: tmp, mode: .replace) { _, _ in }

        #expect(((try? ctx.fetch(FetchDescriptor<Student>())) ?? []).count == 1)
        #expect(((try? ctx.fetch(FetchDescriptor<Lesson>())) ?? []).count == 1)
    }

    @Test("Checksum mismatch rejects import")
    func checksumFailure() async throws {
        let container = try makeBackupTestContainer()
        let ctx = container.mainContext
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(BackupFile.fileExtension)
        let service = BackupService()
        try await service.exportBackup(modelContext: ctx, to: tmp, password: nil) { _, _ in }
        var data = try Data(contentsOf: tmp)
        // Tweak a byte
        if let idx = data.indices.first { data[idx] ^= 0xFF }
        try data.write(to: tmp, options: .atomic)
        await #expect(throws: Error.self) {
            try await service.importBackup(modelContext: ctx, from: tmp, mode: .replace) { _, _ in }
        }
    }

    @Test("Encryption on/off round-trip")
    func encryptionRoundTrip() async throws {
        let container = try makeBackupTestContainer()
        let ctx = container.mainContext
        let s = Student(firstName: "Enc", lastName: "Test", birthday: Date(), level: .lower)
        ctx.insert(s); try ctx.save()
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(BackupFile.fileExtension)
        let service = BackupService()
        let testPassword = "testPassword123"
        try await service.exportBackup(modelContext: ctx, to: tmp, password: testPassword) { _, _ in }
        try await service.importBackup(modelContext: ctx, from: tmp, mode: .merge, password: testPassword) { _, _ in }
        #expect(((try? ctx.fetch(FetchDescriptor<Student>())) ?? []).count >= 1)
    }

    @Test("Typed preferences round-trip")
    func typedPreferencesRoundTrip() async throws {
        let container = try makeBackupTestContainer()
        let ctx = container.mainContext
        // Seed defaults
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "AttendanceEmail.enabled")
        defaults.set(7, forKey: "LessonAge.warningDays")
        defaults.set(3.14, forKey: "lastBackupTimeInterval")
        defaults.set("test@example.com", forKey: "AttendanceEmail.to")

        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(BackupFile.fileExtension)
        let service = BackupService()
        let _ = try await service.exportBackup(modelContext: ctx, to: tmp, password: nil) { _, _ in }

        // Overwrite defaults
        defaults.removeObject(forKey: "AttendanceEmail.enabled")
        defaults.removeObject(forKey: "LessonAge.warningDays")
        defaults.removeObject(forKey: "lastBackupTimeInterval")
        defaults.removeObject(forKey: "AttendanceEmail.to")

        let _ = try await service.importBackup(modelContext: ctx, from: tmp, mode: .merge) { _, _ in }

        #expect(defaults.object(forKey: "AttendanceEmail.enabled") as? Bool == true)
        #expect(defaults.object(forKey: "LessonAge.warningDays") as? Int == 7)
        #expect(defaults.object(forKey: "lastBackupTimeInterval") as? Double == 3.14)
        #expect(defaults.string(forKey: "AttendanceEmail.to") == "test@example.com")
    }

    @Test("Import v1 preferences as strings")
    func importV1Preferences() async throws {
        // Build a v1-like envelope with preferences as [String: String]
        // This tests backward compatibility - v1 used string preferences, current format uses typed PreferencesDTO
        let payloadV1 = ["AttendanceEmail.to": "legacy@example.com"]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601

        // Legacy payload structure matching what v1 backups looked like (string-based preferences)
        struct LegacyPayload: Codable {
            var items: [ItemDTO] = []
            var students: [StudentDTO] = []
            var lessons: [LessonDTO] = []
            var studentLessons: [StudentLessonDTO] = []
            var workPlanItems: [WorkPlanItemDTO] = []
            var scopedNotes: [ScopedNoteDTO] = []
            var notes: [NoteDTO] = []
            var nonSchoolDays: [NonSchoolDayDTO] = []
            var schoolDayOverrides: [SchoolDayOverrideDTO] = []
            var studentMeetings: [StudentMeetingDTO] = []
            var presentations: [PresentationDTO] = []
            var communityTopics: [CommunityTopicDTO] = []
            var proposedSolutions: [ProposedSolutionDTO] = []
            var meetingNotes: [MeetingNoteDTO] = []
            var communityAttachments: [CommunityAttachmentDTO] = []
            var attendance: [AttendanceRecordDTO] = []
            var workCompletions: [WorkCompletionRecordDTO] = []
            var preferences: [String: String]  // v1 used string-based preferences
        }

        let legacy = LegacyPayload(preferences: payloadV1)
        let payloadBytes = try encoder.encode(legacy)
        let sha = SHA256.hash(data: payloadBytes).compactMap { String(format: "%02x", $0) }.joined()
        let envelope = BackupEnvelope(formatVersion: 1, createdAt: Date(), appBuild: "", appVersion: "", device: "", manifest: BackupManifest(entityCounts: [:], sha256: sha, notes: nil), payload: nil, encryptedPayload: payloadBytes)
        let envBytes = try encoder.encode(envelope)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(BackupFile.fileExtension)
        try envBytes.write(to: tmp)

        let container = try makeBackupTestContainer()
        let ctx = container.mainContext
        let service = BackupService()
        let _ = try await service.importBackup(modelContext: ctx, from: tmp, mode: .merge) { _, _ in }
        // Should not crash and should set the legacy preference as a string
        #expect(UserDefaults.standard.string(forKey: "AttendanceEmail.to") == "legacy@example.com")
    }

    @Test("Registry-driven preferences round-trip typed")
    func registryPreferencesRoundTrip() async throws {
        let container = try makeBackupTestContainer()
        let ctx = container.mainContext
        let defaults = UserDefaults.standard
        defaults.set(true, forKey: "Backup.encrypt")
        defaults.set(10, forKey: "LessonAge.warningDays")
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(BackupFile.fileExtension)
        let service = BackupService()
        let _ = try await service.exportBackup(modelContext: ctx, to: tmp, password: nil) { _, _ in }
        defaults.removeObject(forKey: "Backup.encrypt")
        defaults.removeObject(forKey: "LessonAge.warningDays")
        let _ = try await service.importBackup(modelContext: ctx, from: tmp, mode: .merge) { _, _ in }
        #expect(defaults.object(forKey: "Backup.encrypt") as? Bool == true)
        #expect(defaults.object(forKey: "LessonAge.warningDays") as? Int == 10)
    }

    @Test("Validation detects duplicate IDs")
    func validationDuplicateIDs() async throws {
        let container = try makeBackupTestContainer()
        let ctx = container.mainContext
        // Build a payload with duplicate student IDs
        let id = UUID()
        let payload = BackupPayload(items: [], students: [StudentDTO(id: id, firstName: "A", lastName: "B", birthday: Date(), dateStarted: nil, level: .lower, nextLessons: [], manualOrder: 0, createdAt: nil, updatedAt: nil), StudentDTO(id: id, firstName: "C", lastName: "D", birthday: Date(), dateStarted: nil, level: .lower, nextLessons: [], manualOrder: 0, createdAt: nil, updatedAt: nil)], lessons: [], studentLessons: [], lessonAssignments: [], workPlanItems: [], scopedNotes: [], notes: [], nonSchoolDays: [], schoolDayOverrides: [], studentMeetings: [], presentations: [], communityTopics: [], proposedSolutions: [], meetingNotes: [], communityAttachments: [], attendance: [], workCompletions: [], projects: [], projectAssignmentTemplates: [], projectSessions: [], projectRoles: [], projectTemplateWeeks: [], projectWeekRoleAssignments: [], preferences: PreferencesDTO(values: [:]))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(payload)
        let sha = SHA256.hash(data: bytes).compactMap { String(format: "%02x", $0) }.joined()
        let env = BackupEnvelope(formatVersion: BackupFile.formatVersion, createdAt: Date(), appBuild: "", appVersion: "", device: "", manifest: BackupManifest(entityCounts: [:], sha256: sha, notes: nil), payload: payload, encryptedPayload: nil)
        let envBytes = try encoder.encode(env)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(BackupFile.fileExtension)
        try envBytes.write(to: tmp)
        let service = BackupService()
        await #expect(throws: Error.self) {
            let _ = try await service.importBackup(modelContext: ctx, from: tmp, mode: .replace) { _, _ in }
        }
    }

    @Test("Validation warns on dangling references in merge mode")
    func validationDanglingReferencesMerge() async throws {
        let container = try makeBackupTestContainer()
        let ctx = container.mainContext
        let missingLesson = UUID()
        let sl = StudentLessonDTO(id: UUID(), lessonID: missingLesson, studentIDs: [], createdAt: Date(), scheduledFor: nil, givenAt: nil, isPresented: false, notes: "", needsPractice: false, needsAnotherPresentation: false, followUpWork: "", studentGroupKey: nil)
        let payload = BackupPayload(items: [], students: [], lessons: [], studentLessons: [sl], lessonAssignments: [], workPlanItems: [], scopedNotes: [], notes: [], nonSchoolDays: [], schoolDayOverrides: [], studentMeetings: [], presentations: [], communityTopics: [], proposedSolutions: [], meetingNotes: [], communityAttachments: [], attendance: [], workCompletions: [], projects: [], projectAssignmentTemplates: [], projectSessions: [], projectRoles: [], projectTemplateWeeks: [], projectWeekRoleAssignments: [], preferences: PreferencesDTO(values: [:]))
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let bytes = try encoder.encode(payload)
        let sha = SHA256.hash(data: bytes).compactMap { String(format: "%02x", $0) }.joined()
        let env = BackupEnvelope(formatVersion: BackupFile.formatVersion, createdAt: Date(), appBuild: "", appVersion: "", device: "", manifest: BackupManifest(entityCounts: [:], sha256: sha, notes: nil), payload: payload, encryptedPayload: nil)
        let envBytes = try encoder.encode(env)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(BackupFile.fileExtension)
        try envBytes.write(to: tmp)
        let service = BackupService()
        let summary = try await service.importBackup(modelContext: ctx, from: tmp, mode: .merge) { _, _ in }
        #expect(summary.warnings.contains(where: { $0.localizedCaseInsensitiveContains("missing Lesson") }))
    }
}
#endif
