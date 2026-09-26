import CoreData
import Foundation
import Synchronization
import Testing
@testable import CosmicDaybook

/// Stores, seeds and archive readers shared by the streamed-export, preview
/// and peak-memory suites.
@MainActor
enum BackupStreamingFixtures {

    struct ProgressStep: Equatable {
        let fraction: Double
        let message: String
    }

    /// Receives the main-actor progress callback.
    final class ProgressLog {
        var steps: [ProgressStep] = []

        func append(_ fraction: Double, _ message: String) {
            steps.append(ProgressStep(fraction: fraction, message: message))
        }
    }

    /// Lets a recorder act at a phase only the first time (the one-pass
    /// fallback reaches the same phases again).
    nonisolated final class FirstTime: Sendable {
        private let done = Mutex(false)

        func claim() -> Bool {
            done.withLock { done in
                defer { done = true }
                return !done
            }
        }
    }

    /// An on-disk, history-tracked store in its own directory (Sample Class's
    /// shape), so two collections read rows in the same SQLite order.
    struct Store {
        let stack: CoreDataStack
        let directory: URL
        var context: NSManagedObjectContext { stack.viewContext }

        func archiveURL(_ name: String) -> URL {
            directory.appendingPathComponent(name).appendingPathExtension(BackupFile.fileExtension)
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    static func makeStore() throws -> Store {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BackupStreaming-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stack = try CoreDataStack(
            enableCloudKit: false, localStoreURL: directory.appendingPathComponent("Store.sqlite")
        )
        return Store(stack: stack, directory: directory)
    }

    /// Every backed-up type once (the field-coverage fixture), plus notes,
    /// attendance and check-ins past one 1,000-row fetch batch. Every field a
    /// transformer would otherwise fill with `Date()` or `UUID()` is set, so
    /// two collections produce the same rows. Saves.
    static func seedEveryType(in context: NSManagedObjectContext, bulk: Int = 1_000) throws {
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: context)
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let studentID = UUID().uuidString
        let workID = UUID().uuidString
        for index in 0..<(bulk + 205) {
            let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
            note.setValue(UUID(), forKey: "id")
            note.setValue("Observation \(index): chose the bead frame and worked through it twice.", forKey: "body")
            note.setValue(start.addingTimeInterval(Double(index) * 60), forKey: "createdAt")
            note.setValue(start.addingTimeInterval(Double(index) * 60 + 30), forKey: "updatedAt")
        }
        for index in 0..<(bulk + 30) {
            let record = NSEntityDescription.insertNewObject(forEntityName: "AttendanceRecord", into: context)
            record.setValue(UUID(), forKey: "id")
            record.setValue(studentID, forKey: "studentID")
            record.setValue(start.addingTimeInterval(Double(index) * 86_400), forKey: "date")
        }
        for index in 0..<(bulk + 10) {
            let checkIn = NSEntityDescription.insertNewObject(forEntityName: "WorkCheckIn", into: context)
            checkIn.setValue(UUID(), forKey: "id")
            checkIn.setValue(workID, forKey: "workID")
            checkIn.setValue(start.addingTimeInterval(Double(index) * 3_600), forKey: "date")
        }
        try context.save()
    }

    /// Inserts a note with every field the transformer defaults set. Does not
    /// save. Nonisolated: call it on `context`'s queue.
    nonisolated static func insertNote(_ body: String, into context: NSManagedObjectContext) {
        let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: context)
        note.setValue(UUID(), forKey: "id")
        note.setValue(body, forKey: "body")
        note.setValue(Date(timeIntervalSince1970: 1_760_000_000), forKey: "createdAt")
        note.setValue(Date(timeIntervalSince1970: 1_760_000_030), forKey: "updatedAt")
    }

    // MARK: - Reading archives

    /// An archive's decrypted entries, in order.
    struct ArchiveContents {
        var paths: [String] = []
        var bodies: [String: Data] = [:]

        func manifest() throws -> BackupArchiveManifest {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(BackupArchiveManifest.self, from: try #require(bodies["manifest.json"]))
        }
    }

    static func contents(of url: URL) throws -> ArchiveContents {
        var contents = ArchiveContents()
        try BackupArchive.read(
            from: url,
            encryptionKey: { try BackupEncryptionKeyStore.requireKey() },
            consumer: { path, data in
                contents.paths.append(path)
                contents.bodies[path] = data
                return true
            }
        )
        return contents
    }

    /// `preferences.json` exactly as the old writer encoded it.
    static func legacyPreferencesJSON(_ payload: BackupPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload.preferences)
    }

    /// An entity's NDJSON with one thing made comparable. `NoteDTO.scope` is a
    /// JSON string the transformer encodes without sorted keys, and
    /// `JSONEncoder` orders unsorted keys differently from one encode to the
    /// next, so no two collections — old code included — agree on it byte for
    /// byte. Each Note line's scope is rewritten with sorted keys; every other
    /// byte, of every line and every entity, is left exactly as written.
    static func comparable(_ ndjson: Data, entityName: String) throws -> Data {
        guard entityName == "Note" else { return ndjson }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        var result = Data()
        for line in ndjson.split(separator: 0x0A) {
            var bytes = Data(line)
            let object = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            if let scope = object["scope"] as? String {
                let parsed = try JSONSerialization.jsonObject(with: Data(scope.utf8), options: [.fragmentsAllowed])
                let sortedData = try JSONSerialization.data(
                    withJSONObject: parsed, options: [.sortedKeys, .fragmentsAllowed]
                )
                let sorted = try #require(String(bytes: sortedData, encoding: .utf8))
                let written = try encoder.encode(scope)
                let range = try #require(bytes.range(of: written), "the scope as the NDJSON encoder wrote it")
                bytes.replaceSubrange(range, with: try encoder.encode(sorted))
            }
            result.append(bytes)
            result.append(0x0A)
        }
        return result
    }

    /// NDJSON lines in byte order, for comparing rows regardless of order.
    static func sortedLines(_ ndjson: Data) -> [Data] {
        ndjson.split(separator: 0x0A).map { Data($0) }.sorted { $0.lexicographicallyPrecedes($1) }
    }

    /// Expects `archive` to hold exactly what the old export wrote for
    /// `legacy`: manifest, preferences, then every non-empty type's NDJSON in
    /// registry order, byte for byte (the manifest's `createdAt` and the Note
    /// scope's key order aside — see `comparable`). Types in `unordered` are
    /// compared as the same lines in any order.
    static func expectLegacyEntries(
        _ archive: ArchiveContents,
        for legacy: BackupPayload,
        unordered: Set<String> = []
    ) throws {
        let reference = try BackupWriter.serializeEntries(from: legacy)
        let referencePaths = reference.map { "\($0.storeName)/\($0.entityName).ndjson" }
        #expect(archive.paths == ["manifest.json", "preferences.json"] + referencePaths)
        for entry in reference {
            let written = try #require(archive.bodies["\(entry.storeName)/\(entry.entityName).ndjson"])
            let expected = try comparable(entry.ndjson, entityName: entry.entityName)
            let actual = try comparable(written, entityName: entry.entityName)
            if unordered.contains(entry.entityName) {
                #expect(sortedLines(actual) == sortedLines(expected), "\(entry.entityName) differs")
            } else {
                #expect(actual == expected, "\(entry.entityName) differs")
            }
        }
        #expect(archive.bodies["preferences.json"] == (try legacyPreferencesJSON(legacy)))
        let manifest = try archive.manifest()
        let counts = Dictionary(uniqueKeysWithValues: reference.map { ($0.entityName, $0.count) })
        let stores = Dictionary(uniqueKeysWithValues: reference.map { ($0.entityName, $0.storeName) })
        #expect(manifest.formatVersion == BackupWriter.formatVersion)
        #expect(manifest.entityCounts == counts)
        #expect(manifest.originStores == stores)
    }
}
