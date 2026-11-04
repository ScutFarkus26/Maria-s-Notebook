import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Apple Reminders copies, to-do subtasks and to-do templates were retired in
/// Simplify round two (`CoreDataStack.retiredEntities`). A backup made before
/// still restores: their entries are passed over without a warning, and
/// everything else comes back.
///
/// The fixture `BackupRetiredTypes-before.json` beside this file is the
/// golden backup as it was recorded before the change (one row of every
/// backed-up type, the three retired ones included), in the same
/// `<store>/<Entity>` → NDJSON layout as `BackupGolden-v27.json`.
@Suite("Backup: retired types in an older backup", .serialized)
@MainActor
struct RetiredTypesRestoreTests {
    private final class BundleToken {}

    private static let retired = ["Reminder", "TodoSubtask", "TodoTemplate"]

    @Test("An older backup with reminders, subtasks and to-do templates restores without them, and without warnings")
    func olderBackupRestoresWithoutRetiredRows() async throws {
        let fixture = try Self.loadFixture()
        for name in Self.retired {
            #expect(fixture["private/\(name)"] != nil, "the fixture should hold \(name) rows")
        }
        #expect(Set(Self.retired) == BackupEntityTable.skippedOnImport)
        #expect(Set(Self.retired) == CoreDataStack.retiredEntities)

        let entries: [BackupEntityEntry] = fixture.keys.sorted().compactMap { key in
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let body = fixture[key] else { return nil }
            let rows = body.split(separator: "\n", omittingEmptySubsequences: true).count
            return BackupEntityEntry(entityName: parts[1], storeName: parts[0], count: rows, ndjson: Data(body.utf8))
        }
        let decoded = BackupReader.DecodedBackup(
            manifest: BackupArchiveManifest(
                formatVersion: BackupWriter.formatVersion, createdAt: Date(),
                appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
            ),
            entries: entries,
            preferences: nil
        )
        let (payload, warnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(warnings.isEmpty, "\(warnings)")

        let restored = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let summary = try await BackupService().importPayload(
            payload: payload,
            envelope: BackupEnvelope(
                formatVersion: BackupWriter.formatVersion, encrypted: false, createdAt: Date(),
                fileName: "before-retirement", entityCounts: [:]
            ),
            viewContext: restored,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )
        let retiredWarnings = summary.warnings.filter { warning in
            Self.retired.contains { warning.contains($0) } || warning.contains("Unknown entity")
        }
        #expect(retiredWarnings.isEmpty, "\(retiredWarnings)")

        for name in Self.retired {
            let count = try restored.count(for: NSFetchRequest<NSManagedObject>(entityName: name))
            #expect(count == 0, "\(name) rows came back from the backup")
        }
        for name in ["TodoItem", "Note", "WorkModel", "WorkCheckIn"] {
            let expected = Self.rowCount(fixture["private/\(name)"])
            let count = try restored.count(for: NSFetchRequest<NSManagedObject>(entityName: name))
            #expect(expected > 0, "the fixture should hold \(name) rows")
            #expect(count == expected, "\(name): \(count) restored of \(expected)")
        }
    }

    @Test("The preview of an older backup counts nothing for the retired types and warns about none")
    func previewSkipsRetiredTypes() throws {
        let fixture = try Self.loadFixture()
        for name in Self.retired {
            let entry = BackupEntityEntry(
                entityName: name, storeName: "private", count: Self.rowCount(fixture["private/\(name)"]),
                ndjson: Data((fixture["private/\(name)"] ?? "").utf8)
            )
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = BackupDateCoding.decodingStrategy
            var visited = 0
            let warning = BackupImporter.visitRows(of: entry, using: decoder) { _ in visited += 1 }
            #expect(warning == nil, "\(name): \(warning ?? "")")
            #expect(visited == 0, "\(name) rows were read")
        }
    }

    private static func loadFixture() throws -> [String: String] {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: "BackupRetiredTypes-before", withExtension: "json"),
            "Missing BackupRetiredTypes-before.json in the test bundle"
        )
        return try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
    }

    private static func rowCount(_ body: String?) -> Int {
        (body ?? "").split(separator: "\n", omittingEmptySubsequences: true).count
    }
}
