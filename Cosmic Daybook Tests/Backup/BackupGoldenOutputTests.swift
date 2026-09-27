import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Pins the exact bytes the backup writes for a store holding one fully
/// populated instance of every backed-up entity (the field-coverage fixture,
/// deterministic by design), and that those bytes restore to a store that
/// writes them again. Any change to how a row is encoded or decoded — the
/// model-driven backup work of 2026-09 in particular — must leave both intact.
///
/// The reference is `BackupGolden-v27.json` beside this file: one NDJSON body
/// per `<store>/<Entity>` entry. Re-record it only for an intended format
/// change: run with `TEST_RUNNER_RECORD_BACKUP_GOLDEN=1`, and the recording
/// test fails naming the file it wrote, which then replaces the reference.
@Suite("Backup golden output", .serialized)
@MainActor
struct BackupGoldenOutputTests {
    private final class BundleToken {}

    private static let goldenName = "BackupGolden-v27"

    @Test("A backup of the fixture matches the recorded reference byte for byte")
    func exportMatchesGolden() throws {
        let current = try Self.exportFixture()
        if ProcessInfo.processInfo.environment["RECORD_BACKUP_GOLDEN"] == "1" {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(Self.goldenName).json")
            try Self.encode(current).write(to: url)
            Issue.record("Recorded the backup reference to \(url.path); copy it over \(Self.goldenName).json")
            return
        }
        let golden = try #require(try Self.loadGolden(), "Missing \(Self.goldenName).json in the test bundle")
        Self.expectSame(current, golden, context: "export")
    }

    @Test("The recorded reference restores to a store that backs up to the same bytes")
    func goldenRestoresAndReexports() async throws {
        let golden = try #require(try Self.loadGolden(), "Missing \(Self.goldenName).json in the test bundle")
        let restored = try await Self.restore(golden)
        let reexported = try Self.export(restored.viewContext)
        Self.expectSame(reexported, golden, context: "restore then export")
    }

    // MARK: - Helpers

    /// `<store>/<Entity>` → NDJSON body, for every entry the writer produced.
    static func exportFixture() throws -> [String: String] {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: context)
        #expect(CoreDataTestHelpers.save(context), "Fixture save failed")
        return try export(context)
    }

    static func export(_ context: NSManagedObjectContext) throws -> [String: String] {
        let payload = BackupService().collectPayload(viewContext: context)
        let entries = try BackupWriter.serializeEntries(from: payload)
        var bodies: [String: String] = [:]
        for entry in entries {
            bodies["\(entry.storeName)/\(entry.entityName)"] = String(bytes: entry.ndjson, encoding: .utf8) ?? ""
        }
        return bodies
    }

    private static func restore(_ golden: [String: String]) async throws -> CoreDataStack {
        let entries: [BackupEntityEntry] = golden.keys.sorted().compactMap { key in
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let body = golden[key] else { return nil }
            let data = Data(body.utf8)
            let rows = body.split(separator: "\n", omittingEmptySubsequences: true).count
            return BackupEntityEntry(entityName: parts[1], storeName: parts[0], count: rows, ndjson: data)
        }
        let manifest = BackupArchiveManifest(
            formatVersion: BackupWriter.formatVersion, createdAt: Date(),
            appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
        )
        let decoded = BackupReader.DecodedBackup(manifest: manifest, entries: entries, preferences: nil)
        let (payload, warnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(warnings.isEmpty, "The reference decoded with warnings: \(warnings)")

        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await BackupService().importPayload(
            payload: payload,
            envelope: BackupEnvelope(
                formatVersion: BackupWriter.formatVersion, encrypted: false, createdAt: Date(),
                fileName: "golden-restore", entityCounts: manifest.entityCounts
            ),
            viewContext: stack.viewContext,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )
        return stack
    }

    private static func loadGolden() throws -> [String: String]? {
        guard let url = Bundle(for: BundleToken.self).url(forResource: goldenName, withExtension: "json") else {
            return nil
        }
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    private static func encode(_ bodies: [String: String]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        return try encoder.encode(bodies)
    }

    /// An entry's rows, byte for byte except one: a string value that is itself
    /// a JSON object (only `Note.scope`, written from a dictionary with no fixed
    /// key order) is compared by its content.
    private static func rows(_ body: String) -> [String] {
        body.split(separator: "\n").map { line in
            guard line.contains(#""{"#),
                  var row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return String(line)
            }
            for (field, value) in row {
                guard let text = value as? String, text.hasPrefix("{"),
                      let nested = try? JSONSerialization.jsonObject(with: Data(text.utf8)),
                      let sorted = try? JSONSerialization.data(withJSONObject: nested, options: [.sortedKeys]) else {
                    continue
                }
                row[field] = String(bytes: sorted, encoding: .utf8)
            }
            let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
            let data = (try? JSONSerialization.data(withJSONObject: row, options: options)) ?? Data()
            return String(bytes: data, encoding: .utf8) ?? String(line)
        }
    }

    /// Names every entry that differs, and shows the first differing row of each.
    private static func expectSame(_ actual: [String: String], _ golden: [String: String], context: String) {
        let missing = Set(golden.keys).subtracting(actual.keys).sorted()
        let extra = Set(actual.keys).subtracting(golden.keys).sorted()
        #expect(missing.isEmpty, "\(context): entries no longer written: \(missing)")
        #expect(extra.isEmpty, "\(context): entries not in the reference: \(extra)")
        for key in Set(golden.keys).intersection(actual.keys).sorted() {
            let actualRows = rows(actual[key] ?? "")
            let goldenRows = rows(golden[key] ?? "")
            guard actualRows != goldenRows else { continue }
            let firstDiff = zip(actualRows, goldenRows).first { $0 != $1 }
            Issue.record("""
                \(context): \(key) differs from the reference \
                (\(actualRows.count) rows now, \(goldenRows.count) recorded).
                now:      \(firstDiff?.0 ?? actualRows.first ?? "")
                recorded: \(firstDiff?.1 ?? goldenRows.first ?? "")
                """)
        }
    }
}
