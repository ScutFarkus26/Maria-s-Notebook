import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Where each half of the backup pipeline runs. Payload collection reads the
// view context, so it stays on the main actor; everything CPU- and IO-heavy
// (Keychain read, NDJSON encoding, LZFSE + AES, the read-back verification,
// and the decode on restore) runs off it. Until 2026-09-25 the heavy half ran
// on the main thread despite its comments: under NonisolatedNonsendingByDefault
// a plain `nonisolated async` function runs on its caller's actor, and every
// caller is main-actor code. Moving the work must not change a byte of the
// archive or the order progress reaches the UI.
@Suite("Backup pipeline threading")
@MainActor
struct BackupPipelineThreadingTests {

    /// Receives the main-actor progress callback (a `@Sendable` closure
    /// cannot append to a captured local).
    private final class ProgressLog {
        var steps: [(fraction: Double, message: String)] = []
        var offMainCalls = 0
    }

    private static func seededContext() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        let grace = CoreDataTestHelpers.seedStudent(in: context, firstName: "Grace", lastName: "Hopper")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        CoreDataTestHelpers.seedNote(in: context, body: "Ada built the thousand cube")
        CoreDataTestHelpers.seedNote(in: context, body: "Grace wants the bank game")
        CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Bead chain", studentID: ada.id ?? UUID(), lessonID: lesson.id ?? UUID()
        )
        CoreDataTestHelpers.seedAttendance(in: context, studentID: grace.id ?? UUID())
        try context.save()
        return context
    }

    /// A private directory per test, so a leftover temp file is attributable.
    private static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupPipelineThreading-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func archiveURL(in directory: URL) -> URL {
        directory.appendingPathComponent("Backup").appendingPathExtension(BackupFile.fileExtension)
    }

    // MARK: - Threads

    @Test("Export collects on the main thread and encodes, encrypts and verifies off it")
    func exportHeavyHalfRunsOffMain() async throws {
        let context = try Self.seededContext()
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = Self.archiveURL(in: directory)

        let recorder = BackupPipelineRecorder()
        try await BackupPipelineRecorder.$current.withValue(recorder) {
            _ = try await BackupWriter.write(viewContext: context, to: url)
        }

        let steps = recorder.reached
        #expect(steps.first == BackupPipelineRecorder.Step(phase: "collect", onMainThread: true))
        let heavy = steps.dropFirst()
        #expect(heavy.contains { $0.phase == "encode Student" })
        #expect(heavy.contains { $0.phase == "encode Note" })
        #expect(heavy.last?.phase == "verify")
        let onMain = heavy.filter(\.onMainThread).map(\.phase)
        #expect(onMain.isEmpty, "Ran on the main thread: \(onMain)")
        #expect(BackupArchive.isEncryptedArchive(at: url))
    }

    @Test("Restore reads, decrypts and decodes off the main thread")
    func decodeRunsOffMain() async throws {
        let context = try Self.seededContext()
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = Self.archiveURL(in: directory)
        _ = try await BackupWriter.write(viewContext: context, to: url)

        let recorder = BackupPipelineRecorder()
        let archive = try await BackupPipelineRecorder.$current.withValue(recorder) {
            try await BackupImporter.decodeArchive(at: url)
        }

        #expect(recorder.reached == [BackupPipelineRecorder.Step(phase: "decode", onMainThread: false)])
        #expect(archive.payload.students.count == 2)
        #expect(archive.warnings.isEmpty)
    }

    // MARK: - Same bytes

    @Test("The archive holds exactly the bytes the in-memory encoder produces, in registry order")
    func archiveBytesMatchReferenceEncoding() async throws {
        let context = try Self.seededContext()
        let payload = BackupService().collectPayload(viewContext: context)
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = Self.archiveURL(in: directory)

        let manifest = try await BackupWriter.encodeAndWrite(
            payload: payload,
            deviceName: "Test iPad",
            to: url,
            progress: { _, _ in }
        )

        var paths: [String] = []
        var bodies: [String: Data] = [:]
        try BackupArchive.read(
            from: url,
            encryptionKey: { try BackupEncryptionKeyStore.requireKey() },
            consumer: { path, data in
                paths.append(path)
                bodies[path] = data
                return true
            }
        )

        // `serializeEntries` is the synchronous, all-in-memory encoder over the
        // same table; the streamed export must match it byte for byte.
        let reference = try BackupWriter.serializeEntries(from: payload)
        #expect(reference.count >= 5)
        let referencePaths = reference.map { "\($0.storeName)/\($0.entityName).ndjson" }
        #expect(paths == ["manifest.json", "preferences.json"] + referencePaths)
        for entry in reference {
            #expect(bodies["\(entry.storeName)/\(entry.entityName).ndjson"] == entry.ndjson, "\(entry.entityName)")
        }

        let preferencesEncoder = JSONEncoder()
        preferencesEncoder.outputFormatting = [.sortedKeys]
        preferencesEncoder.dateEncodingStrategy = .iso8601
        let expectedPreferences = try preferencesEncoder.encode(payload.preferences)
        #expect(bodies["preferences.json"] == expectedPreferences)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifestData = try #require(bodies["manifest.json"])
        let written = try decoder.decode(BackupArchiveManifest.self, from: manifestData)
        #expect(written.formatVersion == BackupWriter.formatVersion)
        #expect(written.device == "Test iPad")
        #expect(written.entityCounts == manifest.entityCounts)
        #expect(written.originStores == manifest.originStores)
        #expect(written.entityCounts == Dictionary(uniqueKeysWithValues: reference.map { ($0.entityName, $0.count) }))
    }

    // MARK: - Progress

    @Test("Progress reaches the main actor in the same order through every step")
    func progressStillReachesMainActorInOrder() async throws {
        let context = try Self.seededContext()
        let directory = try Self.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = Self.archiveURL(in: directory)

        let log = ProgressLog()
        _ = try await BackupWriter.write(viewContext: context, to: url) { fraction, message in
            log.steps.append((fraction, message))
            if !Thread.isMainThread { log.offMainCalls += 1 }
        }

        #expect(log.offMainCalls == 0)
        #expect(log.steps.first?.fraction == 0.0)
        #expect(log.steps.first?.message == "Collecting entities\u{2026}")
        let tail = log.steps.suffix(4)
        #expect(tail.map(\.fraction) == [0.65, 0.75, 0.9, 1.0])
        #expect(tail.map(\.message) == [
            "Encoding\u{2026}", "Writing archive\u{2026}", "Verifying\u{2026}", "Backup complete"
        ])
        let collecting = log.steps.dropLast(4).map(\.fraction)
        #expect(collecting.allSatisfy { $0 <= 0.6 })
    }
}
