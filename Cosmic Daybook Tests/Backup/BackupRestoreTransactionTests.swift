import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// How a restore fails, and what runs where. Broken archives throw the one-pass
// restore's errors (BackupService+LegacyRestore.swift) and leave the store
// untouched; a replace restore failing part-way changes nothing (its clear is
// saved with its records, 2026-10-05) and one failing after its save rolls
// back to its checkpoint;
// a merge restore failing part-way (2026-09-27; it used to leave its partial
// changes pending, for the next save anywhere to commit) discards exactly its
// own changes and keeps the guide's unsaved edits, which it saves first; every
// backed-up type is imported once, in the old order; and the archive decodes
// off the main thread while nothing else runs on the main actor from the clear
// to the save.
@Suite("Backup restore failures and threads", .serialized)
@MainActor
struct BackupRestoreTransactionTests {
    private typealias Restore = BackupRestoreFixtures
    private typealias Fixtures = BackupStreamingFixtures

    private struct Boom: Error {}

    private static func coordinator() -> BackupCoordinator {
        BackupCoordinator(
            backupService: BackupService(), transactionManager: BackupTransactionManager(), appRouter: AppRouter()
        )
    }

    /// A recorder that fails the restore the first time it reaches `phase`.
    private static func failing(at phase: String) -> BackupPipelineRecorder {
        let once = Fixtures.FirstTime()
        return Restore.recorder(failure: { reached in
            guard reached == phase, once.claim() else { return nil }
            return Boom()
        })
    }

    /// The types a recorder saw imported before it reached `phase`.
    private static func imported(before phase: String, in recorder: BackupPipelineRecorder) -> [String] {
        let steps = recorder.reached.map(\.phase)
        let end = steps.firstIndex(of: phase) ?? steps.endIndex
        return steps[..<end].filter { $0.hasPrefix("import ") }
    }

    // MARK: - Failures

    @Test("No manifest, or a bad entry path: the old errors, and the store untouched")
    func brokenArchivesThrowTheOldErrors() async throws {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let source = try Fixtures.contents(of: url)
        let noManifest = store.archiveURL("NoManifest")
        try Restore.writeArchive(
            source.paths.filter { $0 != "manifest.json" }.map { ($0, source.bodies[$0] ?? Data()) },
            to: noManifest
        )
        let badPath = store.archiveURL("BadPath")
        try Restore.writeArchive(
            source.paths.map { ($0, source.bodies[$0] ?? Data()) } + [("loose.ndjson", Data("{}\n".utf8))],
            to: badPath
        )

        let target = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await Restore.restore(url, into: target.viewContext, mode: .merge)
        let before = try Restore.snapshot(of: target.viewContext)
        for broken in [noManifest, badPath] {
            var oldError: String?
            var newError: String?
            do { _ = try await Restore.legacyRestore(broken, into: target.viewContext, mode: .replace) } catch {
                oldError = error.localizedDescription
            }
            do { _ = try await Restore.restore(broken, into: target.viewContext, mode: .replace) } catch {
                newError = error.localizedDescription
            }
            #expect(oldError != nil)
            #expect(newError == oldError, "\(broken.lastPathComponent)")
            #expect(try Restore.snapshot(of: target.viewContext) == before, "\(broken.lastPathComponent)")
        }
    }

    /// Replaces `target` with another notebook's backup that fails at
    /// `phase`; returns the checkpoint the failure reported and the recorder.
    private static func failedReplace(
        of target: NSManagedObjectContext, at phase: String
    ) async throws -> (checkpoint: URL?, recorder: BackupPipelineRecorder) {
        let other = try Fixtures.makeStore()
        defer { other.remove() }
        try Fixtures.seedEveryType(in: other.context, bulk: 20)
        let otherURL = other.archiveURL("Other")
        try await Restore.writeBackup(of: other.context, to: otherURL)
        let recorder = Self.failing(at: phase)

        var checkpoint: URL?
        do {
            _ = try await BackupPipelineRecorder.$current.withValue(recorder) {
                try await Self.coordinator().importBackup(
                    viewContext: target, from: otherURL, mode: .replace, progress: { _, _ in }
                )
            }
            Issue.record("The restore should have failed")
        } catch BackupTransactionManager.TransactionError.importFailed(let underlying, let checkpointURL) {
            #expect(underlying is Boom)
            checkpoint = checkpointURL
        }
        if let checkpoint { try? FileManager.default.removeItem(at: checkpoint) }
        return (checkpoint, recorder)
    }

    /// Every Student's and Note's object, to tell kept records from re-added ones.
    private static func objects(in context: NSManagedObjectContext) throws -> Set<NSManagedObjectID> {
        let students = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Student"))
        let notes = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Note"))
        return Set((students + notes).map(\.objectID))
    }

    @Test("A replace restore failing part-way, before its save, changes nothing and needs no checkpoint")
    func failedReplaceBeforeSavingChangesNothing() async throws {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await Restore.restore(url, into: target.viewContext, mode: .merge)
        let before = try Restore.backedUpRows(of: target.viewContext)
        let objects = try Self.objects(in: target.viewContext)

        let (checkpoint, recorder) = try await Self.failedReplace(of: target.viewContext, at: "import WorkModel")

        #expect(checkpoint == nil, "nothing to go back to: the clear is saved only with the import")
        let importedFirst = Self.imported(before: "import WorkModel", in: recorder)
        #expect(importedFirst.count > 10, "types imported before the failure: \(importedFirst.count)")
        #expect(try Restore.backedUpRows(of: target.viewContext) == before)
        #expect(try Self.objects(in: target.viewContext) == objects, "the same records, not re-added copies")
        #expect(!target.viewContext.hasChanges)
    }

    @Test("A replace restore failing after its save rolls back to the checkpoint")
    func failedReplaceAfterSavingRollsBack() async throws {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await Restore.restore(url, into: target.viewContext, mode: .merge)
        let before = try Restore.backedUpRows(of: target.viewContext)

        let (checkpoint, _) = try await Self.failedReplace(of: target.viewContext, at: "saved")

        #expect(checkpoint != nil, "restored from a checkpoint")
        #expect(try Restore.backedUpRows(of: target.viewContext) == before)
        #expect(!target.viewContext.hasChanges)
    }

    @Test("A merge restore failing part-way discards exactly its own changes and keeps the guide's")
    func failedMergeDiscardsOnlyItsOwnChanges() async throws {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let studentID = try #require(try await BackupImporter.decodeArchive(at: url).payload.students.first?.id)
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        let context = target.viewContext
        // Saved: a student the backup also holds — a restore would overwrite her.
        let student = NSEntityDescription.insertNewObject(forEntityName: "Student", into: context)
        student.setValue(studentID, forKey: "id")
        student.setValue("Before", forKey: "firstName")
        try context.save()
        // Not saved when the restore begins: an edit to her, and a new note.
        student.setValue("Edited, not saved", forKey: "firstName")
        let typedID = UUID()
        let typed = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
        typed.setValue(typedID, forKey: "id")
        typed.setValue("Typed, not saved", forKey: "body")

        let recorder = Self.failing(at: "import WorkModel")
        do {
            _ = try await BackupPipelineRecorder.$current.withValue(recorder) {
                try await Self.coordinator().importBackup(
                    viewContext: context, from: url, mode: .merge, progress: { _, _ in }
                )
            }
            Issue.record("The restore should have failed")
        } catch BackupTransactionManager.TransactionError.importFailed(let underlying, let checkpointURL) {
            #expect(underlying is Boom)
            #expect(checkpointURL == nil, "a merge restore makes no checkpoint")
        }
        #expect(Self.imported(before: "import WorkModel", in: recorder).count > 10)

        // Nothing is left for the next save to commit, and the store holds the
        // guide's edits and nothing of the backup's.
        #expect(!context.hasChanges)
        context.refreshAllObjects()
        let rows = try Restore.snapshot(of: context)
        #expect(rows.keys.sorted() == ["Note", "Student"], "only the guide's records: \(rows.keys.sorted())")
        let students = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Student"))
        #expect(students.map { $0.value(forKey: "firstName") as? String } == ["Edited, not saved"])
        let notes = try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Note"))
        #expect(notes.map { $0.value(forKey: "id") as? UUID } == [typedID])
    }

    // MARK: - Order and threads

    /// Hands the restore empty types and remembers which it asked for.
    private final class SpySource: BackupRestoreSource {
        let envelope = BackupEnvelope(
            formatVersion: BackupWriter.formatVersion, encrypted: true, createdAt: Date(),
            fileName: "spy", entityCounts: [:]
        )
        let preferences = PreferencesDTO(values: [:])
        var asked: [String] = []

        func rows(of entity: BackupEntity) -> BackupPayload {
            asked.append(entity.name)
            return BackupPayload.collecting(preferences: preferences)
        }
    }

    @Test("The restore asks for every backed-up type once, parents first")
    func everyTypeOnceInOrder() async throws {
        let spy = SpySource()
        _ = try await BackupService().importRows(
            from: spy, viewContext: try CoreDataTestHelpers.makeContext(), mode: .merge,
            appRouter: AppRouter(), progress: { _, _ in }
        )
        #expect(spy.asked == Restore.restoreOrder)
        #expect(spy.asked.sorted() == BackupEntityTable.names.sorted())
    }

    /// What a main-actor task queued part-way through a restore saw when it ran.
    private final class TurnLook {
        let context: NSManagedObjectContext
        var unsavedChanges: Bool?
        var students = -1

        init(context: NSManagedObjectContext) {
            self.context = context
        }

        func take() {
            unsavedChanges = context.hasChanges
            students = (try? context.count(for: NSFetchRequest<NSManagedObject>(entityName: "Student"))) ?? -1
        }
    }

    @Test("The archive decodes off the main thread; nothing else runs on the main actor from the clear to the save")
    func decodeOffMainImportInOneTurn() async throws {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        let look = TurnLook(context: target.viewContext)
        let once = Fixtures.FirstTime()
        let recorder = Restore.recorder(onPhase: { phase in
            guard phase.hasPrefix("import "), once.claim() else { return }
            Task { @MainActor in look.take() }
        })
        _ = try await BackupPipelineRecorder.$current.withValue(recorder) {
            try await BackupImporter.restore(
                from: url, into: target.viewContext, mode: .replace, appRouter: AppRouter(), progress: { _, _ in }
            )
        }

        let steps = recorder.reached
        #expect(steps.first == BackupPipelineRecorder.Step(phase: "decode", onMainThread: false))
        let imports = steps.dropFirst().filter { $0.phase.hasPrefix("import ") }
        let importedOnMain = imports.allSatisfy(\.onMainThread)
        #expect(importedOnMain, "types imported in the main-actor turn")
        #expect(imports.map { String($0.phase.dropFirst("import ".count)) } == Restore.restoreOrder)
        #expect(look.unsavedChanges == false, "a main-actor task ran while the restore was unsaved")
        let students = try Restore.snapshot(of: target.viewContext)["Student"]?.count
        #expect(students != nil && look.students == students, "the task saw every restored student")
    }
}
