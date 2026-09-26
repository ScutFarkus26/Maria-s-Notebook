import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The export collects, encodes and packs one entity type at a time instead of
// holding the whole database as DTOs (2026-09-26). Pinned here: the archive
// is the old export's archive — same entries, same order, same bytes — on a
// store holding every backed-up type with several types past one 1,000-row
// fetch batch; the collector table reads what the old collector read, with the
// same progress lines; a change landing mid-stream (or unsaved edits at the
// start) sends the export back to the one-pass path, so an archive is always
// one moment; and a background export stopped mid-write leaves nothing.
@Suite("Backup streamed export")
@MainActor
struct BackupStreamingExportTests {
    private typealias Fixtures = BackupStreamingFixtures

    // MARK: - Tables

    @Test("The collector table lists the writer's entity types, in archive order")
    func collectorTableMatchesWriterTable() {
        #expect(BackupService.entityCollectors.map(\.entityName) == BackupWriter.serializedEntityNames)
        #expect(BackupWriter.collectorsMatchSerializations)
    }

    @Test("collectPayload reads what the old collector read, with the same progress lines")
    func collectorTableMatchesLegacyCollector() throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Fixtures.seedEveryType(in: store.context)
        let service = BackupService()

        let tableLog = Fixtures.ProgressLog()
        let legacyLog = Fixtures.ProgressLog()
        let (table, legacy) = BackupPipelineRecorder.$current.withValue(Fixtures.recorder()) {
            (
                service.collectPayload(viewContext: store.context) { tableLog.append($0, $1) },
                service.legacyCollectPayload(viewContext: store.context) { legacyLog.append($0, $1) }
            )
        }

        #expect(tableLog.steps == legacyLog.steps)
        #expect(!tableLog.steps.isEmpty)
        let tableEntries = try BackupWriter.serializeEntries(from: table)
        let legacyEntries = try BackupWriter.serializeEntries(from: legacy)
        #expect(tableEntries.map(\.entityName) == BackupWriter.serializedEntityNames, "every type is in the fixture")
        #expect(tableEntries.map(\.entityName) == legacyEntries.map(\.entityName))
        for (new, old) in zip(tableEntries, legacyEntries) {
            #expect(new.count == old.count, "\(new.entityName)")
            let newBytes = try Fixtures.comparable(new.ndjson, entityName: new.entityName)
            #expect(newBytes == (try Fixtures.comparable(old.ndjson, entityName: old.entityName)), "\(new.entityName)")
        }
        #expect(table.preferences.values == Fixtures.preferences.values, "read through buildPreferencesDTO")
        #expect((try Fixtures.legacyPreferencesJSON(table)) == (try Fixtures.legacyPreferencesJSON(legacy)))
    }

    // MARK: - Same archive

    @Test("The streamed archive is the old export's archive: same entries, order and bytes")
    func streamedArchiveMatchesLegacyExport() async throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Fixtures.seedEveryType(in: store.context)
        let url = store.archiveURL("Streamed")

        let recorder = Fixtures.recorder()
        let summary = try await BackupPipelineRecorder.$current.withValue(recorder) {
            try await BackupWriter.write(viewContext: store.context, to: url)
        }

        let phases = recorder.reached.map(\.phase)
        #expect(phases.contains("write staged"), "the export streamed: \(phases)")
        #expect(!phases.contains("collect in one pass"))
        #expect(summary.entityCounts["Note"] == 1_206)
        #expect(summary.entityCounts["AttendanceRecord"] == 1_031)
        #expect(summary.entityCounts["WorkCheckIn"] == 1_011)

        let streamed = try Fixtures.contents(of: url)
        let legacy = Fixtures.legacyPayload(of: store.context)
        try Fixtures.expectLegacyEntries(streamed, for: legacy)

        // And the one-pass path, fed the old collector's payload, writes the same file.
        let onePassURL = store.archiveURL("OnePass")
        _ = try await BackupWriter.encodeAndWrite(
            payload: legacy, deviceName: try streamed.manifest().device, to: onePassURL, progress: { _, _ in }
        )
        let onePass = try Fixtures.contents(of: onePassURL)
        #expect(onePass.paths == streamed.paths)
        for path in streamed.paths where path != "manifest.json" {
            let entity = String(path.split(separator: "/").last?.split(separator: ".").first ?? "")
            let onePassBytes = try Fixtures.comparable(try #require(onePass.bodies[path]), entityName: entity)
            #expect(onePassBytes == (try Fixtures.comparable(try #require(streamed.bodies[path]), entityName: entity)))
        }
        var streamedManifest = try streamed.manifest()
        streamedManifest.createdAt = try onePass.manifest().createdAt
        #expect(streamedManifest == (try onePass.manifest()))
    }

    @Test("An in-memory stack streams too (no persistent history to consult)")
    func inMemoryStackStreams() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: context)
        try context.save()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupStreamingMemory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Backup").appendingPathExtension(BackupFile.fileExtension)

        let recorder = Fixtures.recorder()
        try await BackupPipelineRecorder.$current.withValue(recorder) {
            _ = try await BackupWriter.write(viewContext: context, to: url)
        }

        #expect(recorder.reached.map(\.phase).contains("write staged"))
        let legacy = Fixtures.legacyPayload(of: context)
        try Fixtures.expectLegacyEntries(try Fixtures.contents(of: url), for: legacy)
    }

    // MARK: - One moment

    @Test("A save landing mid-stream sends the export back to one pass; the archive is one moment")
    func saveMidStreamFallsBackToOnePass() async throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Fixtures.seedEveryType(in: store.context)
        let background = store.stack.container.newBackgroundContext()
        let once = Fixtures.FirstTime()
        // Once the students are encoded, a background context saves a note —
        // how a CloudKit import lands while the main actor is free.
        let recorder = Fixtures.recorder { phase in
            guard phase == "encode Student", once.claim() else { return }
            background.performAndWait {
                Fixtures.insertNote("Arrived mid-export", into: background)
                try? background.save()
            }
        }
        let url = store.archiveURL("Fallback")

        let summary = try await BackupPipelineRecorder.$current.withValue(recorder) {
            try await BackupWriter.write(viewContext: store.context, to: url)
        }

        let phases = recorder.reached.map(\.phase)
        #expect(phases.contains("collect in one pass"), "\(phases)")
        #expect(!phases.contains("write staged"))
        #expect(phases.last == "verify")
        #expect(summary.entityCounts["Note"] == 1_207, "the one-pass collection saw the new note")
        // Nothing has changed since, so the archive is the old export of the store as it is now.
        let legacy = Fixtures.legacyPayload(of: store.context)
        try Fixtures.expectLegacyEntries(try Fixtures.contents(of: url), for: legacy)
    }

    /// Unsaved edits mean the one-pass export, the old code, runs unchanged.
    /// What it collects of unsaved edits past one 1,000-row page (it once wrote
    /// such an insert twice) is pinned in `BackupCollectionPagingTests`.
    @Test("Unsaved edits keep the one-pass export, pending rows and all")
    func unsavedEditsUseOnePass() async throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Fixtures.seedEveryType(in: store.context)
        let students = try store.context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Student"))
        try #require(students.first).setValue("Renamed, not saved", forKey: "firstName")
        let lesson = NSEntityDescription.insertNewObject(forEntityName: "Lesson", into: store.context)
        lesson.setValue(UUID(), forKey: "id")
        lesson.setValue("Typed but not saved", forKey: "name")
        let url = store.archiveURL("Pending")

        let recorder = Fixtures.recorder()
        let summary = try await BackupPipelineRecorder.$current.withValue(recorder) {
            try await BackupWriter.write(viewContext: store.context, to: url)
        }

        let phases = recorder.reached.map(\.phase)
        #expect(!phases.contains("write staged"))
        #expect(!phases.contains("collect in one pass"), "declined before collecting anything")
        #expect(summary.entityCounts["Lesson"] == 2, "the pending lesson is in the backup")
        let legacy = Fixtures.legacyPayload(of: store.context)
        #expect(legacy.students.contains { $0.firstName == "Renamed, not saved" })
        try Fixtures.expectLegacyEntries(try Fixtures.contents(of: url), for: legacy, unordered: ["Lesson"])
    }

    @Test("The watch hears edits and saves, and ignores a quiet store")
    func watchHearsEditsAndSaves() throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Fixtures.seedEveryType(in: store.context, bulk: 0)

        let watch = try #require(BackupSnapshotWatch(viewContext: store.context))
        #expect(!watch.sawChange(in: store.context))
        #expect(!watch.sawChangeAtEnd(in: store.context))

        let background = store.stack.container.newBackgroundContext()
        background.performAndWait {
            Fixtures.insertNote("Saved elsewhere", into: background)
            try? background.save()
        }
        #expect(watch.sawChange(in: store.context), "a save on the same coordinator")

        let students = try store.context.fetch(NSFetchRequest<NSManagedObject>(entityName: "Student"))
        let student = try #require(students.first)
        student.setValue("Renamed", forKey: "firstName")
        #expect(BackupSnapshotWatch(viewContext: store.context) == nil, "unsaved edits: the one-pass export")
        #expect(watch.sawChange(in: store.context), "an edit on the view context, announced or not")
    }

    @Test("Persistent history catches a save whose notification the watch never heard")
    func historyCatchesUnheardSave() throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Fixtures.seedEveryType(in: store.context, bulk: 0)
        // A private notification center: the flag hears nothing Core Data posts.
        let watch = try #require(BackupSnapshotWatch(viewContext: store.context, center: NotificationCenter()))
        #expect(!watch.sawChangeAtEnd(in: store.context))

        let background = store.stack.container.newBackgroundContext()
        background.performAndWait {
            Fixtures.insertNote("Saved unheard", into: background)
            try? background.save()
        }

        #expect(!watch.sawChange(in: store.context), "the flag never heard the save")
        #expect(watch.sawChangeAtEnd(in: store.context), "the history did")
    }

    // MARK: - Progress and stopping

    @Test("The streamed export reports the old export's progress lines, in order")
    func streamedProgressMatchesLegacyExport() async throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Fixtures.seedEveryType(in: store.context, bulk: 0)

        let streamed = Fixtures.ProgressLog()
        _ = try await BackupWriter.write(viewContext: store.context, to: store.archiveURL("Progress")) {
            streamed.append($0, $1)
        }

        let legacy = Fixtures.ProgressLog()
        legacy.append(0.0, "Collecting entities\u{2026}")
        _ = BackupService().legacyCollectPayload(viewContext: store.context) {
            legacy.append(min(0.6, $0 * 0.6), $1)
        }
        legacy.append(0.65, "Encoding\u{2026}")
        legacy.append(0.75, "Writing archive\u{2026}")
        legacy.append(0.9, "Verifying\u{2026}")
        legacy.append(1.0, "Backup complete")
        #expect(streamed.steps == legacy.steps)
    }

    @Test("A background export stopped while the staged archive is written leaves nothing")
    func stoppedWhileWritingLeavesNothing() async throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Fixtures.seedEveryType(in: store.context, bulk: 0)
        let exports = store.directory.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let url = exports.appendingPathComponent("AutoBackup").appendingPathExtension(BackupFile.fileExtension)
        let recorder = BackupPipelineRecorder { phase in
            if phase == "write staged" { withUnsafeCurrentTask { $0?.cancel() } }
        }
        let context = store.context

        let export = Task { @MainActor in
            try await BackupPipelineRecorder.$current.withValue(recorder) {
                try await BackupWriter.write(viewContext: context, to: url, stopsWhenCancelled: true)
            }
        }
        let result = await export.result

        #expect(throws: CancellationError.self) { try result.get() }
        let phases = recorder.reached.map(\.phase)
        #expect(phases.contains("write staged"))
        #expect(!phases.contains("verify"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: exports.path).isEmpty)
    }
}
