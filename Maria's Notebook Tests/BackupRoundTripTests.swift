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

    static func writeCurrentBackup(from context: NSManagedObjectContext, to url: URL) throws {
        _ = try BackupWriter.write(viewContext: context, to: url, progress: noopProgress)
    }

    static func importCurrentBackup(
        from url: URL,
        into context: NSManagedObjectContext,
        mode: BackupService.RestoreMode
    ) async throws {
        let decoded = try BackupReader.read(from: url)
        _ = try await BackupImporter.importDecoded(
            decoded,
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

        try BackupTestUtil.writeCurrentBackup(from: sourceStack.viewContext, to: url)
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

    @Test("Current backup file verifies as compressed archive")
    func compressedArchive() throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        BackupTestUtil.seedBasicFixture(in: sourceStack.viewContext)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }

        try BackupTestUtil.writeCurrentBackup(from: sourceStack.viewContext, to: url)

        let info = try BackupVerification.verifyBackup(at: url).get()
        #expect(
            info.isCompressed,
            "Expected current backup archive to report compression"
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

        try BackupTestUtil.writeCurrentBackup(from: sourceStack.viewContext, to: url)

        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        try await BackupTestUtil.importCurrentBackup(from: url, into: destStack.viewContext, mode: .merge)

        let request = NSFetchRequest<CDStudent>(entityName: "Student")
        let restored = try destStack.viewContext.fetch(request)
        let match = restored.first { $0.firstName == "Maria" && $0.lastName == "Montessori" }
        let matchedStudent = try #require(match, "Restored student not found by name")
        #expect(matchedStudent.id == expectedID, "Student ID changed during round-trip")
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

        try BackupTestUtil.writeCurrentBackup(from: sourceStack.viewContext, to: url)

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

        try BackupTestUtil.writeCurrentBackup(from: sourceStack.viewContext, to: url)

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

// MARK: - Suite 3b: Backup2 (v17 AEA) round-trip

@Suite("Backup2 v17 AEA round-trip")
@MainActor
final class Backup2RoundTripTests {

    @Test("v17 AEA file: writes magic bytes, round-trips through reader+importer")
    func aeaRoundTrip() async throws {
        // Build a source stack with the standard fixture and export via BackupWriter.
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        let expected = BackupTestUtil.seedBasicFixture(in: sourceStack.viewContext)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }

        let exportSummary = try BackupWriter.write(
            viewContext: sourceStack.viewContext,
            to: url,
            progress: { _, _ in }
        )
        #expect(exportSummary.formatVersion == BackupWriter.formatVersion)
        #expect(exportSummary.encryptUsed == false)
        #expect(FileManager.default.fileExists(atPath: url.path))

        // Magic bytes assertion: the file must start with AEA's "AA01" so the
        // coordinator detects it as a Backup2 file (not legacy JSON envelope).
        #expect(BackupArchive.isAEAFormat(at: url),
                "Backup2 export must produce an AEA-framed file (first 4 bytes = AA01)")

        // Round-trip: decode + import into a fresh stack.
        let decoded = try BackupReader.read(from: url)
        #expect(decoded.manifest.formatVersion == BackupWriter.formatVersion)
        #expect(!decoded.entries.isEmpty, "Decoded backup should have at least one entry")

        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await BackupImporter.importDecoded(
            decoded,
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
                "Entity \(entityName) count mismatch after v17 restore: expected \(expectedCount), got \(actual)"
            )
        }
    }

    @Test("v17 AEA file verifies successfully through BackupVerification")
    func aeaVerificationSucceeds() throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        BackupTestUtil.seedBasicFixture(in: sourceStack.viewContext)

        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }

        _ = try BackupWriter.write(
            viewContext: sourceStack.viewContext,
            to: url,
            progress: { _, _ in }
        )

        let result = BackupVerification.verifyBackup(at: url)
        let info = try result.get()
        #expect(info.formatVersion == BackupWriter.formatVersion)
        #expect(info.isCompressed)
        #expect(info.entityCounts["Student"] ?? 0 >= 2)
    }

    @Test("Coordinator: legacy file detection returns false on a v16 envelope")
    func coordinatorDetectsLegacyFormat() throws {
        // Construct a minimal legacy-style file (starts with `{`, not "AA01").
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try Data("{\"formatVersion\":16}".utf8).write(to: url)

        #expect(!BackupArchive.isAEAFormat(at: url),
                "Files starting with `{` should be classified as legacy, not AEA")
    }

    @Test("v17 reader rejects a non-AEA file with a helpful error")
    func readerRejectsNonAEAFile() throws {
        let url = BackupTestUtil.tempBackupURL()
        defer { BackupTestUtil.cleanup(url) }
        try Data("not a valid backup".utf8).write(to: url)

        var threw = false
        do {
            _ = try BackupReader.read(from: url)
        } catch BackupReader.ReadError.notAEAFormat {
            threw = true
        } catch {
            Issue.record("Reader threw unexpected error type: \(error)")
        }
        #expect(threw, "Reader must throw notAEAFormat for files without the AA01 magic")
    }
}
