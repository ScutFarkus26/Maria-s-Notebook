import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Format 45 dropped the track entities with schema 23
/// (`docs/Plans/Plan - Retire the track entities.md`, Phase 3). A backup made
/// before that still holds `Track`, `TrackStep`, `SequenceTrack` and
/// `StudentTrackEnrollment` entries, and `trackID`, `trackStepID` and
/// `studentTrackEnrollmentID` on presentations, assignments, work and notes.
///
/// The fixture, `BackupGolden-v44.json`, is the golden reference as format 44
/// wrote it: one fully populated record of every type backed up then. It must
/// read without a warning (the track entries are no newer version's) and
/// restore every other record, field for field.
@Suite("A format-44 backup's track entries", .serialized)
@MainActor
struct BackupRetiredTrackEntriesTests {
    private final class BundleToken {}

    private static let fixtureName = "BackupGolden-v44"
    private static let retiredFields: Set<String> = ["trackID", "trackStepID", "studentTrackEnrollmentID"]

    @Test("A v44 backup with track entries reads without a warning and restores everything else")
    func v44BackupRestores() async throws {
        let url = try #require(
            Bundle(for: BundleToken.self).url(forResource: Self.fixtureName, withExtension: "json"),
            "Missing \(Self.fixtureName).json in the test bundle"
        )
        let v44 = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        // The fixture really holds what left.
        for name in BackupEntityTable.retiredNames {
            #expect(!(v44["private/\(name)"] ?? "").isEmpty, "the fixture has no \(name) rows")
        }
        #expect(v44["private/Note"]?.contains(#""studentTrackEnrollmentID""#) == true)
        #expect(v44["private/WorkModel"]?.contains(#""trackStepID""#) == true)

        let entries = Self.entries(v44)
        let manifest = BackupArchiveManifest(
            formatVersion: 44, createdAt: Date(),
            appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
        )
        let decoded = BackupReader.DecodedBackup(manifest: manifest, entries: entries, preferences: nil)
        #expect(BackupReader.supportedFormatVersions.contains(44))
        let (payload, warnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(warnings.isEmpty, "The v44 backup decoded with warnings: \(warnings)")

        // The preview's walk reads it without a warning too.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = BackupDateCoding.decodingStrategy
        for entry in entries {
            #expect(
                BackupImporter.visitRows(of: entry, using: decoder) { _ in } == nil,
                "\(entry.entityName) warned in the preview"
            )
        }

        let stack = try await Self.restore(payload)

        // Backed up again: every entry but the track ones, every field but
        // the ones that named a track. Types a restore leaves alone (this
        // device's classroom pin) come back out only if the store had them.
        let reexported = try BackupGoldenOutputTests.export(stack.viewContext)
        let expected = v44.filter { key, _ in
            let name = String(key.split(separator: "/").last ?? "")
            return !BackupEntityTable.retiredNames.contains(name)
                && !BackupEntityRegistry.keptOnRestoreEntityNames.contains(name)
        }
        #expect(Set(reexported.keys) == Set(expected.keys))
        for (key, body) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(
                Self.rows(reexported[key] ?? "") == Self.rows(body, dropping: Self.retiredFields),
                "\(key) came back different"
            )
        }
    }

    /// `<store>/<Entity>` → NDJSON body, as the archive's entries.
    private static func entries(_ bodies: [String: String]) -> [BackupEntityEntry] {
        bodies.keys.sorted().compactMap { key in
            let parts = key.split(separator: "/", maxSplits: 1).map(String.init)
            guard parts.count == 2, let body = bodies[key] else { return nil }
            let rows = body.split(separator: "\n", omittingEmptySubsequences: true).count
            return BackupEntityEntry(entityName: parts[1], storeName: parts[0], count: rows, ndjson: Data(body.utf8))
        }
    }

    /// A merge restore of `payload`, made from a format-44 backup, into a new store.
    private static func restore(_ payload: BackupPayload) async throws -> CoreDataStack {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await BackupService().importPayload(
            payload: payload,
            envelope: BackupEnvelope(
                formatVersion: 44, encrypted: false, createdAt: Date(),
                fileName: "v44-tracks", entityCounts: [:]
            ),
            viewContext: stack.viewContext,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )
        return stack
    }

    /// An entry's rows as sorted-key JSON, sorted, without `dropping`; a string
    /// value that is itself a JSON object (a note's scope, written with no fixed
    /// key order) compared by its content.
    private static func rows(_ body: String, dropping: Set<String> = []) -> [String] {
        body.split(separator: "\n").map { line in
            guard var row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return String(line)
            }
            for field in dropping { row[field] = nil }
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
        .sorted()
    }
}
