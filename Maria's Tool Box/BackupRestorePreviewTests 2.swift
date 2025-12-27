import Foundation
import SwiftData
import CryptoKit
#if canImport(Testing)
import Testing
#endif

#if canImport(Testing)
@Suite("Restore Preview tests")
struct BackupRestorePreviewTests {
    // Helper to write an envelope with the provided payload
    private func writeEnvelope(with payload: BackupPayload) throws -> URL {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let payloadBytes = try encoder.encode(payload)
        let sha = SHA256.hash(data: payloadBytes).map { String(format: "%02x", $0) }.joined()
        // Build counts map for manifest for completeness
        let counts: [String: Int] = [
            "Student": payload.students.count,
            "Lesson": payload.lessons.count,
            "StudentLesson": payload.studentLessons.count,
            "WorkContract": payload.workContracts.count,
            "WorkPlanItem": payload.workPlanItems.count,
            "ScopedNote": payload.scopedNotes.count,
            "Note": payload.notes.count,
            "NonSchoolDay": payload.nonSchoolDays.count,
            "SchoolDayOverride": payload.schoolDayOverrides.count,
            "StudentMeeting": payload.studentMeetings.count,
            "Presentation": payload.presentations.count,
            "CommunityTopic": payload.communityTopics.count,
            "ProposedSolution": payload.proposedSolutions.count,
            "MeetingNote": payload.meetingNotes.count,
            "CommunityAttachment": payload.communityAttachments.count
        ]
        let env = BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: Date(),
            appBuild: "",
            appVersion: "",
            device: "",
            manifest: BackupManifest(entityCounts: counts, sha256: sha, notes: nil),
            payload: payload,
            encryptedPayload: nil
        )
        let envBytes = try encoder.encode(env)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(BackupFile.fileExtension)
        try envBytes.write(to: url)
        return url
    }

    private func makeOneOfEachPayload() -> BackupPayload {
        let now = Date()
        let studentID = UUID()
        let lessonID = UUID()
        let student = StudentDTO(id: studentID, firstName: "A", lastName: "B", birthday: now, dateStarted: nil, level: .lower, nextLessons: [], manualOrder: 0, createdAt: nil, updatedAt: nil)
        let lesson = LessonDTO(id: lessonID, name: "L", subject: "S", group: "G", orderInGroup: 1, subheading: "", writeUp: "", createdAt: nil, updatedAt: nil, pagesFileRelativePath: nil)
        let sl = StudentLessonDTO(id: UUID(), lessonID: lessonID, studentIDs: [studentID], createdAt: now, scheduledFor: nil, givenAt: nil, isPresented: false, notes: "", needsPractice: false, needsAnotherPresentation: false, followUpWork: "", studentGroupKey: nil)
        let contract = WorkContractDTO(id: UUID(), studentID: studentID.uuidString, lessonID: lessonID.uuidString, presentationID: nil, status: "active", scheduledDate: nil, createdAt: now, completedAt: nil, kind: nil, scheduledReason: nil, scheduledNote: nil, completionOutcome: nil, completionNote: nil, legacyStudentLessonID: nil)
        let wpi = WorkPlanItemDTO(id: UUID(), workID: UUID(), scheduledDate: now, reason: "inbox", note: nil)
        let scoped = ScopedNoteDTO(id: UUID(), createdAt: now, updatedAt: now, body: "body", scope: "general", legacyFingerprint: nil, studentLessonID: nil, workID: nil, presentationID: nil, workContractID: nil)
        let note = NoteDTO(id: UUID(), createdAt: now, updatedAt: now, body: "body", isPinned: false, scope: "general", lessonID: nil, workID: nil)
        let nsd = NonSchoolDayDTO(id: UUID(), date: now, reason: nil)
        let sdo = SchoolDayOverrideDTO(id: UUID(), date: now, note: nil)
        let meeting = StudentMeetingDTO(id: UUID(), studentID: studentID, date: now, completed: false, reflection: "", focus: "", requests: "", guideNotes: "")
        let pres = PresentationDTO(id: UUID(), createdAt: now, presentedAt: now, lessonID: lessonID.uuidString, studentIDs: [studentID.uuidString], legacyStudentLessonID: nil, lessonTitleSnapshot: nil, lessonSubtitleSnapshot: nil)
        let topicID = UUID()
        let topic = CommunityTopicDTO(id: topicID, title: "T", issueDescription: "I", createdAt: now, addressedDate: nil, resolution: "", raisedBy: "", tags: [])
        let solution = ProposedSolutionDTO(id: UUID(), topicID: topicID, title: "PS", details: "", proposedBy: "", createdAt: now, isAdopted: false)
        let mn = MeetingNoteDTO(id: UUID(), topicID: topicID, speaker: "S", content: "C", createdAt: now)
        let attach = CommunityAttachmentDTO(id: UUID(), topicID: topicID, filename: "f.txt", kind: "file", createdAt: now)
        let prefs = PreferencesDTO(values: [:])
        return BackupPayload(items: [], students: [student], lessons: [lesson], studentLessons: [sl], workContracts: [contract], workPlanItems: [wpi], scopedNotes: [scoped], notes: [note], nonSchoolDays: [nsd], schoolDayOverrides: [sdo], studentMeetings: [meeting], presentations: [pres], communityTopics: [topic], proposedSolutions: [solution], meetingNotes: [mn], communityAttachments: [attach], preferences: prefs)
    }

    @Test("Merge mode preview shows all inserts on empty store, then skips after import")
    func previewMergeInsertsThenSkips() async throws {
        guard let container = try? ModelContainer(for: Student.self, Lesson.self, StudentLesson.self, WorkContract.self, WorkPlanItem.self, ScopedNote.self, Note.self, NonSchoolDay.self, SchoolDayOverride.self, StudentMeeting.self, Presentation.self, CommunityTopic.self, ProposedSolution.self, MeetingNote.self, CommunityAttachment.self) else { throw Skip("SwiftData models unavailable in test context") }
        let ctx = container.mainContext
        let payload = makeOneOfEachPayload()
        let url = try writeEnvelope(with: payload)

        let service = BackupService()
        let preview1 = try await service.previewImport(modelContext: ctx, from: url, mode: .merge) { _, _ in }
        // All inserts should be 1 for each entity present
        #expect(preview1.totalInserts >= 15)
        #expect(preview1.totalDeletes == 0)

        // Import
        let _ = try await service.importBackup(modelContext: ctx, from: url, mode: .merge) { _, _ in }

        // Second preview should mainly show skips
        let preview2 = try await service.previewImport(modelContext: ctx, from: url, mode: .merge) { _, _ in }
        #expect(preview2.entitySkips.values.reduce(0, +) >= 15)
    }

    @Test("Replace mode preview shows deletes and inserts")
    func previewReplaceShowsDeletesAndInserts() async throws {
        guard let container = try? ModelContainer(for: Student.self, Lesson.self, StudentLesson.self, WorkContract.self, WorkPlanItem.self, ScopedNote.self, Note.self, NonSchoolDay.self, SchoolDayOverride.self, StudentMeeting.self, Presentation.self, CommunityTopic.self, ProposedSolution.self, MeetingNote.self, CommunityAttachment.self) else { throw Skip("SwiftData models unavailable in test context") }
        let ctx = container.mainContext

        // Seed minimal store state
        let s = Student(firstName: "Seed", lastName: "User", birthday: Date(), level: .lower)
        let l = Lesson(name: "L", subject: "S", group: "G", subheading: "", writeUp: "")
        ctx.insert(s); ctx.insert(l); try ctx.save()

        let payload = makeOneOfEachPayload()
        let url = try writeEnvelope(with: payload)
        let service = BackupService()
        let preview = try await service.previewImport(modelContext: ctx, from: url, mode: .replace) { _, _ in }

        // At least some deletes should be > 0 (for Student/Lesson), and inserts should match payload counts
        #expect((preview.entityDeletes["Student"] ?? 0) >= 1)
        #expect((preview.entityDeletes["Lesson"] ?? 0) >= 1)
        #expect((preview.entityInserts["Student"] ?? 0) == payload.students.count)
        #expect((preview.entityInserts["Lesson"] ?? 0) == payload.lessons.count)
    }
}
#endif
