import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// How a restore fails, and what runs where. Broken archives throw the one-pass
// restore's errors (BackupService+LegacyRestore.swift) and leave the store
// untouched; a replace restore failing part-way rolls back to its checkpoint;
// every backed-up type is imported once, in the old order; and the archive
// decodes off the main thread while nothing else runs on the main actor from
// the clear to the save.
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

    @Test("A failure part-way through a replace restore rolls back to the checkpoint")
    func failedReplaceRollsBack() async throws {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let target = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await Restore.restore(url, into: target.viewContext, mode: .merge)
        let before = try Restore.backedUpRows(of: target.viewContext)

        // Replaced by another notebook's backup, which fails at its work.
        let other = try Fixtures.makeStore()
        defer { other.remove() }
        try Fixtures.seedEveryType(in: other.context, bulk: 20)
        let otherURL = other.archiveURL("Other")
        try await Restore.writeBackup(of: other.context, to: otherURL)
        let recorder = Self.failing(at: "import WorkModel")

        var checkpoint: URL?
        do {
            _ = try await BackupPipelineRecorder.$current.withValue(recorder) {
                try await Self.coordinator().importBackup(
                    viewContext: target.viewContext, from: otherURL, mode: .replace, progress: { _, _ in }
                )
            }
            Issue.record("The restore should have failed")
        } catch BackupTransactionManager.TransactionError.importFailed(let underlying, let checkpointURL) {
            #expect(underlying is Boom)
            checkpoint = checkpointURL
        }
        if let checkpoint { try? FileManager.default.removeItem(at: checkpoint) }
        #expect(checkpoint != nil, "restored from a checkpoint")
        let importedFirst = Self.imported(before: "import WorkModel", in: recorder)
        #expect(importedFirst.count > 10, "types imported before the failure: \(importedFirst.count)")
        #expect(try Restore.backedUpRows(of: target.viewContext) == before)
        #expect(!target.viewContext.hasChanges)
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
        let imports = steps.dropFirst()
        let importedOnMain = imports.allSatisfy(\.onMainThread)
        #expect(importedOnMain, "types imported in the main-actor turn")
        #expect(imports.map { String($0.phase.dropFirst("import ".count)) } == Restore.restoreOrder)
        #expect(look.unsavedChanges == false, "a main-actor task ran while the restore was unsaved")
        let students = try Restore.snapshot(of: target.viewContext)["Student"]?.count
        #expect(students != nil && look.students == students, "the task saw every restored student")
    }
}
