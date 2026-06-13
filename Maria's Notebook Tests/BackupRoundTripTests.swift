import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

// MARK: - Shared Helpers

@MainActor
private enum BackupTestUtil {
    /// Produces a fresh temp file URL with the correct extension. Caller is responsible for removing it.
    static func tempBackupURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(BackupFile.fileExtension)
    }

    /// Silently removes a file if it exists. Safe to call in defer.
    static func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// No-op progress callback for tests that don't care about UI updates.
    static let noopProgress: BackupService.ProgressCallback = { _, _ in }

    static func writeCurrentBackup(from context: NSManagedObjectContext, to url: URL) async throws {
        _ = try await BackupWriter.write(viewContext: context, to: url, progress: noopProgress)
    }

    static func importCurrentBackup(
        from url: URL,
        into context: NSManagedObjectContext,
        mode: BackupService.RestoreMode
    ) async throws {
        let archive = try await BackupImporter.decodeArchive(at: url)
        _ = try await BackupImporter.importDecoded(
            archive,
            from: url,
            into: context,
            mode: mode,
            appRouter: AppRouter.shared,
            progress: noopProgress
        )
    }

    /// Seeds a representative fixture spanning common user-visible entity types.
    /// Returns a snapshot of (entityName -> count) for round-trip comparison.
    @discardableResult
    static func seedBasicFixture(in context: NSManagedObjectContext) -> [String: Int] {
        let s1 = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        let s2 = CoreDataTestHelpers.seedStudent(in: context, firstName: "Grace", lastName: "Hopper")
        let l1 = CoreDataTestHelpers.seedLesson(in: context, name: "Counting Bars")
        _ = CoreDataTestHelpers.seedLesson(in: context, name: "Spindle Boxes")
        _ = CoreDataTestHelpers.seedNote(in: context, body: "Ada loved the activity")
        _ = CoreDataTestHelpers.seedNote(in: context, body: "Grace needs a follow-up")
        _ = CoreDataTestHelpers.seedNote(in: context, body: "Reminder: get more beads")
        _ = CoreDataTestHelpers.seedWorkModel(
            in: context,
            title: "Bead Chain Practice",
            studentID: s1.id ?? UUID(),
            lessonID: l1.id ?? UUID()
        )
        _ = CoreDataTestHelpers.seedAttendance(in: context, studentID: s2.id ?? UUID())
        _ = CoreDataTestHelpers.seedClassroomMembership(in: context)
        #expect(CoreDataTestHelpers.save(context), "Fixture save failed")
        return [
            "Student": 2,
            "Lesson": 2,
            "Note": 3,
            "WorkModel": 1,
            "AttendanceRecord": 1,
            "ClassroomMembership": 1
        ]
    }

    /// Counts rows for an entity by name in the given context.
    static func count(entityName: String, in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        return try context.count(for: request)
    }

    /// Fetches a single entity of `type` by its `id` (the app's String/UUID primary key).
    static func fetchByID<T: NSManagedObject>(
        _ type: T.Type,
        _ id: UUID?,
        entityName: String,
        in context: NSManagedObjectContext
    ) throws -> T? {
        guard let id else { return nil }
        let request = NSFetchRequest<T>(entityName: entityName)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

// MARK: - Suite 1: End-to-End Round Trip with Real Core Data
//
// NOTE: These tests use `.merge` mode, NOT `.replace`. The replace path calls
// `NSBatchDeleteRequest` which is unsupported on `NSInMemoryStoreType` stores
// (it raises an ObjC exception that can crash the test harness). Since we
// restore into a FRESH in-memory stack, merge into an empty destination is
// functionally equivalent to replace for our purposes.

@Suite("Backup round-trip with real Core Data")
@MainActor
final class BackupRoundTripTests {

    @Test("Plaintext backup: seeded data round-trips through export + restore")
    func plaintextRoundTrip() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        let expected = BackupTestUtil.seedBasicFixture(in: sourceStack.viewContext)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }

        try await BackupTestUtil.writeCurrentBackup(from: sourceStack.viewContext, to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))

        // Verify the file is structurally valid.
        let info = try BackupVerification.verifyBackup(at: url).get()
        #expect(info.formatVersion == BackupWriter.formatVersion)
        #expect(info.entityCounts["Student"] ?? 0 >= 2)
        #expect(info.entityCounts["Lesson"] ?? 0 >= 2)

        // Restore into a FRESH stack (merge into empty == replace).
        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        try await BackupTestUtil.importCurrentBackup(from: url, into: destStack.viewContext, mode: .merge)

        for (entityName, expectedCount) in expected {
            let actual = try BackupTestUtil.count(entityName: entityName, in: destStack.viewContext)
            #expect(
                actual >= expectedCount,
                "Entity \(entityName) count mismatch after restore: expected \(expectedCount), got \(actual)"
            )
        }
    }

    @Test("Current backup file verifies as compressed, encrypted archive")
    func compressedArchive() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        BackupTestUtil.seedBasicFixture(in: sourceStack.viewContext)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }

        try await BackupTestUtil.writeCurrentBackup(from: sourceStack.viewContext, to: url)

        let info = try BackupVerification.verifyBackup(at: url).get()
        #expect(
            info.isCompressed,
            "Expected current backup archive to report compression"
        )
        #expect(
            info.isEncrypted,
            "Expected current backup archive to report encryption (v19 AEA)"
        )
    }

    @Test("Backup-then-restore preserves student field values (not just counts)")
    func studentFieldsAreFullyRestored() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        let student = CoreDataTestHelpers.seedStudent(
            in: sourceStack.viewContext,
            firstName: "Maria",
            lastName: "Montessori"
        )
        let expectedID = student.id
        #expect(CoreDataTestHelpers.save(sourceStack.viewContext))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }

        try await BackupTestUtil.writeCurrentBackup(from: sourceStack.viewContext, to: url)

        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        try await BackupTestUtil.importCurrentBackup(from: url, into: destStack.viewContext, mode: .merge)

        let request = NSFetchRequest<CDStudent>(entityName: "Student")
        let restored = try destStack.viewContext.fetch(request)
        let match = restored.first { $0.firstName == "Maria" && $0.lastName == "Montessori" }
        let matchedStudent = try #require(match, "Restored student not found by name")
        #expect(matchedStudent.id == expectedID, "Student ID changed during round-trip")
    }

    @Test("Report flags and manual-unblock survive a full backup round-trip")
    func reportRelevantFlagsAreRestored() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = sourceStack.viewContext

        // A note flagged for the report, with author attribution.
        let note = CoreDataTestHelpers.seedNote(in: ctx, body: "Ada mastered the bead chain")
        note.id = UUID()
        note.includeInReport = true
        note.reportedBy = "assistant-123"
        note.reporterName = "Ms. Frizzle"
        note.communityTopicID = "topic-xyz"
        let noteID = note.id

        // A manually-unblocked lesson assignment.
        let assignment = CDLessonAssignment(context: ctx)
        assignment.lessonID = UUID().uuidString
        assignment.studentIDs = [UUID().uuidString]
        assignment.stateRaw = LessonAssignmentState.draft.rawValue
        assignment.manuallyUnblocked = true
        let assignmentID = assignment.id

        #expect(CoreDataTestHelpers.save(ctx))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: ctx, to: url)

        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        try await BackupTestUtil.importCurrentBackup(from: url, into: destStack.viewContext, mode: .merge)
        let dctx = destStack.viewContext

        let restoredNote = try #require(
            try BackupTestUtil.fetchByID(CDNote.self, noteID, entityName: "Note", in: dctx),
            "Restored note not found"
        )
        #expect(restoredNote.includeInReport, "includeInReport must survive the backup round-trip")
        #expect(restoredNote.reportedBy == "assistant-123", "reportedBy must survive the round-trip")
        #expect(restoredNote.reporterName == "Ms. Frizzle", "reporterName must survive the round-trip")
        #expect(restoredNote.communityTopicID == "topic-xyz", "note context link must survive the round-trip")

        let restoredAssignment = try #require(
            try BackupTestUtil.fetchByID(
                CDLessonAssignment.self, assignmentID, entityName: "LessonAssignment", in: dctx
            ),
            "Restored lesson assignment not found"
        )
        #expect(restoredAssignment.manuallyUnblocked, "manuallyUnblocked must survive the backup round-trip")
    }

    @Test("Lesson and Student audited fields survive a full backup round-trip")
    func lessonAndStudentFieldsAreRestored() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = sourceStack.viewContext

        let lesson = CoreDataTestHelpers.seedLesson(in: ctx, name: "Parshat Noach Study")
        lesson.id = UUID()
        lesson.parshaKey = "noach"
        lesson.greatLessonRaw = "secondGreatLesson"
        lesson.lessonFormatRaw = "story"
        lesson.sortIndex = 7
        lesson.requiresPracticeOverride = "required"
        let lessonID = lesson.id

        let student = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Eli", lastName: "Cohen")
        student.id = UUID()
        student.nickname = "Eli"
        student.enrollmentStatusRaw = "withdrawn"
        student.dateWithdrawn = Date(timeIntervalSince1970: 1_700_000_000)
        let studentID = student.id

        #expect(CoreDataTestHelpers.save(ctx))

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try await BackupTestUtil.writeCurrentBackup(from: ctx, to: url)

        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        try await BackupTestUtil.importCurrentBackup(from: url, into: destStack.viewContext, mode: .merge)
        let dctx = destStack.viewContext

        let rl = try #require(
            try BackupTestUtil.fetchByID(CDLesson.self, lessonID, entityName: "Lesson", in: dctx),
            "Restored lesson not found"
        )
        #expect(rl.parshaKey == "noach", "parshaKey must survive the round-trip")
        #expect(rl.greatLessonRaw == "secondGreatLesson", "greatLessonRaw must survive")
        #expect(rl.lessonFormatRaw == "story", "lessonFormatRaw must survive")
        #expect(rl.sortIndex == 7, "sortIndex must survive")
        #expect(rl.requiresPracticeOverride == "required", "requiresPracticeOverride must survive")

        let rs = try #require(
            try BackupTestUtil.fetchByID(CDStudent.self, studentID, entityName: "Student", in: dctx),
            "Restored student not found"
        )
        #expect(rs.nickname == "Eli", "nickname must survive the round-trip")
        #expect(rs.enrollmentStatusRaw == "withdrawn", "enrollment status must survive the round-trip")
        #expect(rs.dateWithdrawn != nil, "dateWithdrawn must survive the round-trip")
    }
}

// MARK: - Suite 2: Registry Coverage

@Suite("Backup entity registry coverage")
@MainActor
final class BackupRegistryCoverageTests {

    @Test("Format version remains defined")
    func formatVersionIsCurrent() {
        #expect(BackupFile.formatVersion > 0)
    }

    @Test("Registry contains the user-visible core entity types")
    func registryCoversCoreUserData() {
        let types = BackupEntityRegistry.allTypes
        let requiredTypes: [NSManagedObject.Type] = [
            CDStudent.self,
            CDLesson.self,
            CDLessonAssignment.self,
            CDLessonPresentation.self,
            CDLessonAttachment.self,
            CDNote.self,
            CDNoteStudentLink.self,
            CDWorkModel.self,
            CDWorkCheckIn.self,
            CDWorkStep.self,
            CDAttendanceRecord.self,
            CDStudentMeeting.self,
            CDProject.self,
            CDProjectSession.self,
            CDTodoItem.self,
            CDReminder.self,
            CDCalendarEvent.self,
            CDCalendarNote.self,
            CDClassroomMembership.self,
            CDMeetingWorkReview.self,
            CDStudentFocusItem.self
        ]
        for type in requiredTypes {
            #expect(
                types.contains(where: { $0 == type }),
                "Entity \(type) is missing from BackupEntityRegistry.allTypes"
            )
        }
    }

    @Test("Registry has no duplicate entries")
    func registryHasNoDuplicates() {
        let typeNames = BackupEntityRegistry.allTypes.map { String(describing: $0) }
        #expect(
            typeNames.count == Set(typeNames).count,
            "BackupEntityRegistry.allTypes contains duplicates: \(typeNames)"
        )
    }
}

// MARK: - Suite 3: Merge Mode and Corruption

@Suite("Backup merge mode + corruption detection")
@MainActor
final class BackupRestoreModeTests {

    @Test("Merge mode preserves existing data and adds new entities")
    func mergeModePreservesExistingData() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        BackupTestUtil.seedBasicFixture(in: sourceStack.viewContext)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }

        try await BackupTestUtil.writeCurrentBackup(from: sourceStack.viewContext, to: url)

        // Destination starts with one distinct student; merge should not drop it.
        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        CoreDataTestHelpers.seedStudent(in: destStack.viewContext, firstName: "Marie", lastName: "Curie")
        #expect(CoreDataTestHelpers.save(destStack.viewContext))

        try await BackupTestUtil.importCurrentBackup(from: url, into: destStack.viewContext, mode: .merge)

        let total = try BackupTestUtil.count(entityName: "Student", in: destStack.viewContext)
        // 2 seeded + 1 existing (Marie) = 3 minimum. Merge must not wipe the original row.
        #expect(total >= 3, "Merge mode dropped pre-existing data: \(total) students")
    }

    @Test("Corrupted backup file is rejected, not silently imported")
    func corruptedFileIsRejected() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        BackupTestUtil.seedBasicFixture(in: sourceStack.viewContext)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }

        try await BackupTestUtil.writeCurrentBackup(from: sourceStack.viewContext, to: url)

        // Corrupt by truncating the last 100 bytes — enough to break the archive.
        var data = try Data(contentsOf: url)
        #expect(data.count > 100)
        data.removeLast(100)
        try data.write(to: url)

        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        var corruptThrew = false
        do {
            try await BackupTestUtil.importCurrentBackup(from: url, into: destStack.viewContext, mode: .merge)
        } catch {
            corruptThrew = true
        }
        #expect(corruptThrew, "Corrupted backup should have been rejected")
    }
}

// MARK: - Suite 3b: Backup2 archive round-trip (v19 encrypted)

@Suite("Backup2 archive round-trip")
@MainActor
final class Backup2RoundTripTests {

    @Test("v19 file: encrypted AA01 container, round-trips through reader+importer")
    func archiveRoundTrip() async throws {
        // Build a source stack with the standard fixture and export via BackupWriter.
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        let expected = BackupTestUtil.seedBasicFixture(in: sourceStack.viewContext)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }

        let exportSummary = try await BackupWriter.write(
            viewContext: sourceStack.viewContext,
            to: url,
            progress: { _, _ in }
        )
        #expect(exportSummary.formatVersion == BackupWriter.formatVersion)
        #expect(exportSummary.encryptUsed == true)
        #expect(FileManager.default.fileExists(atPath: url.path))

        // Magic bytes: v19 files are genuine Apple Encrypted Archives ("AEA1").
        #expect(BackupArchive.isBackupArchive(at: url),
                "Export must produce a readable backup archive")
        #expect(BackupArchive.isEncryptedArchive(at: url),
                "v19 export must produce an encrypted AEA container (first 4 bytes = AEA1)")

        // Round-trip: decode + import into a fresh stack.
        let archive = try await BackupImporter.decodeArchive(at: url)
        #expect(archive.manifest.formatVersion == BackupWriter.formatVersion)
        #expect(archive.warnings.isEmpty, "Clean archive should decode without warnings")

        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await BackupImporter.importDecoded(
            archive,
            from: url,
            into: destStack.viewContext,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )

        for (entityName, expectedCount) in expected {
            let actual = try BackupTestUtil.count(entityName: entityName, in: destStack.viewContext)
            #expect(
                actual >= expectedCount,
                "Entity \(entityName) count mismatch after restore: expected \(expectedCount), got \(actual)"
            )
        }
    }

    @Test("v19 file verifies successfully through BackupVerification")
    func archiveVerificationSucceeds() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        BackupTestUtil.seedBasicFixture(in: sourceStack.viewContext)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }

        _ = try await BackupWriter.write(
            viewContext: sourceStack.viewContext,
            to: url,
            progress: { _, _ in }
        )

        let result = BackupVerification.verifyBackup(at: url)
        let info = try result.get()
        #expect(info.formatVersion == BackupWriter.formatVersion)
        #expect(info.isCompressed)
        #expect(info.isEncrypted)
        #expect(info.entityCounts["Student"] ?? 0 >= 2)
    }

    @Test("Coordinator: legacy file detection returns false on a v16 envelope")
    func coordinatorDetectsLegacyFormat() throws {
        // Construct a minimal legacy-style file (starts with `{`, not an archive magic).
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try Data("{\"formatVersion\":16}".utf8).write(to: url)

        #expect(!BackupArchive.isBackupArchive(at: url),
                "Files starting with `{` should be classified as legacy, not archive")
    }

    @Test("Reader rejects a non-archive file with a helpful error")
    func readerRejectsNonArchiveFile() throws {
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try Data("not a valid backup".utf8).write(to: url)

        var threw = false
        do {
            _ = try BackupReader.read(from: url)
        } catch BackupReader.ReadError.notArchiveFormat {
            threw = true
        } catch {
            Issue.record("Reader threw unexpected error type: \(error)")
        }
        #expect(threw, "Reader must throw notArchiveFormat for files without a known magic")
    }

    /// Round-trips the seeded `ctx` through the full v18 serialization layer —
    /// `collectPayload` (export) -> NDJSON entries -> `reconstructPayload`
    /// (decode/dispatch) -> the shared `importPayload` -> a fresh in-memory stack
    /// (merge into empty == replace). Returns the destination stack (kept alive by
    /// the caller so its `viewContext` stays valid through assertions).
    ///
    /// This deliberately bypasses the AppleArchive (`.mtbbackup`) file container so
    /// the per-entity DTO/transformer/importer logic is verifiable even where
    /// AppleArchive file I/O is unavailable. The container framing itself is
    /// entity-agnostic and is covered by `aeaRoundTrip`.
    private static func roundTripV18(_ ctx: NSManagedObjectContext) async throws -> CoreDataStack {
        let service = BackupService()
        let payload = service.collectPayload(viewContext: ctx)
        let entries = try BackupWriter.serializeEntries(from: payload)
        let manifest = BackupArchiveManifest(
            formatVersion: BackupWriter.formatVersion, createdAt: Date(),
            appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
        )
        let decoded = BackupReader.DecodedBackup(
            manifest: manifest, entries: entries, preferences: payload.preferences
        )
        let (reconstructed, reconstructWarnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(reconstructWarnings.isEmpty, "Round-trip should decode without warnings")

        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await service.importPayload(
            payload: reconstructed,
            envelopeFormatVersion: BackupWriter.formatVersion,
            envelopeEncrypted: false,
            envelopeCreatedAt: Date(),
            envelopeFileName: "v18-roundtrip",
            envelopeEntityCounts: manifest.entityCounts,
            viewContext: destStack.viewContext,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )
        return destStack
    }

    @Test("v18: Day Pad, Year Plan, and Lesson Sequence Settings round-trip")
    func v18PlanningEntitiesRoundTrip() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = sourceStack.viewContext

        // Whole-second date so it survives ISO8601 (second-precision) encoding.
        let dayPadDay = Date(timeIntervalSince1970: 1_700_000_000)
        let dayPad = CDDayPad(context: ctx, day: dayPadDay)
        dayPad.body = "Refill the bead cabinet"
        let dayPadID = dayPad.id

        let yearPlan = CDYearPlanEntry(context: ctx)
        let studentID = UUID().uuidString
        yearPlan.studentID = studentID
        yearPlan.lessonID = UUID().uuidString
        yearPlan.spacingSchoolDays = 5
        yearPlan.orderInSequence = 2
        yearPlan.statusRaw = YearPlanEntryStatus.promoted.rawValue
        let yearPlanID = yearPlan.id

        let settings = CDLessonSequenceSettings(context: ctx)
        settings.area = "Mathematics"
        settings.sequence = "Decimal System"
        settings.requiresPractice = false
        settings.requiresTeacherConfirmation = true
        let settingsID = settings.id

        #expect(CoreDataTestHelpers.save(ctx))
        let destStack = try await Self.roundTripV18(ctx)
        let dctx = destStack.viewContext

        let pad = try #require(try BackupTestUtil.fetchByID(CDDayPad.self, dayPadID, entityName: "DayPad", in: dctx))
        #expect(pad.body == "Refill the bead cabinet")
        #expect(pad.day == dayPadDay)

        let plan = try #require(
            try BackupTestUtil.fetchByID(CDYearPlanEntry.self, yearPlanID, entityName: "YearPlanEntry", in: dctx)
        )
        #expect(plan.studentID == studentID)
        #expect(plan.spacingSchoolDays == 5)
        #expect(plan.orderInSequence == 2)
        #expect(plan.statusRaw == YearPlanEntryStatus.promoted.rawValue)

        let restoredSettings = try #require(
            try BackupTestUtil.fetchByID(
                CDLessonSequenceSettings.self, settingsID, entityName: "LessonSequenceSettings", in: dctx
            )
        )
        #expect(restoredSettings.area == "Mathematics")
        #expect(restoredSettings.requiresPractice == false)
        #expect(restoredSettings.requiresTeacherConfirmation == true)
    }

    @Test("v18: Story round-trips themes + path; binary blobs excluded")
    func v18StoryRoundTrip() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = sourceStack.viewContext

        let story = CDStory(context: ctx)
        story.title = "The Great Lesson"
        story.summary = "An origin story"
        story.themesArray = ["cosmos", "gratitude"]
        story.pdfFileRelativePath = "Stories/great-lesson.pdf"
        story.pageCount = 12
        story.thumbnailData = Data([0x01, 0x02, 0x03])
        let storyID = story.id

        #expect(CoreDataTestHelpers.save(ctx))
        let destStack = try await Self.roundTripV18(ctx)
        let dctx = destStack.viewContext

        let restored = try #require(try BackupTestUtil.fetchByID(CDStory.self, storyID, entityName: "Story", in: dctx))
        #expect(restored.title == "The Great Lesson")
        #expect(restored.themesArray == ["cosmos", "gratitude"])
        #expect(restored.pdfFileRelativePath == "Stories/great-lesson.pdf")
        #expect(restored.pageCount == 12)
        #expect(restored.thumbnailData == nil, "Binary blobs must be excluded from backups")
    }

    @Test("v18: Book Club packet/session/meeting round-trip; meeting -> session re-wired")
    func v18BookClubRoundTrip() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = sourceStack.viewContext

        let packet = CDBookClubPacket(context: ctx)
        packet.title = "Charlotte's Web"
        packet.themesArray = ["friendship"]
        packet.packetPDFRelativePath = "BookClub/charlottes-web.pdf"
        let packetID = packet.id

        let session = CDBookClubSession(context: ctx)
        session.packetID = (packetID ?? UUID()).uuidString
        session.displayName = "Fall Book Club"
        session.statusRaw = BookClubSessionStatus.planned.rawValue
        let sessionID = session.id

        let meeting = CDBookClubMeeting(context: ctx)
        meeting.sessionID = (sessionID ?? UUID()).uuidString
        meeting.ordinal = 1
        meeting.readingLabel = "Chapters 1-3"
        let meetingID = meeting.id

        #expect(CoreDataTestHelpers.save(ctx))
        let destStack = try await Self.roundTripV18(ctx)
        let dctx = destStack.viewContext

        let restoredPacket = try #require(
            try BackupTestUtil.fetchByID(CDBookClubPacket.self, packetID, entityName: "BookClubPacket", in: dctx)
        )
        #expect(restoredPacket.title == "Charlotte's Web")
        #expect(restoredPacket.themesArray == ["friendship"])

        let restoredSession = try #require(
            try BackupTestUtil.fetchByID(CDBookClubSession.self, sessionID, entityName: "BookClubSession", in: dctx)
        )
        #expect(restoredSession.displayName == "Fall Book Club")

        let restoredMeeting = try #require(
            try BackupTestUtil.fetchByID(CDBookClubMeeting.self, meetingID, entityName: "BookClubMeeting", in: dctx)
        )
        #expect(restoredMeeting.readingLabel == "Chapters 1-3")
        // The session relationship (inverse of BookClubSession.meetings) must be re-wired.
        #expect(restoredMeeting.session?.id == sessionID, "Meeting -> session relationship was not restored")
        #expect(
            restoredSession.orderedMeetings.contains { $0.id == meetingID },
            "Session -> meetings inverse was not populated"
        )
    }
}
