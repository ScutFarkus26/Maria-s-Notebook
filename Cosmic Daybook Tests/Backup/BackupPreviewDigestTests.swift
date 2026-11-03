import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The restore preview reads a digest — row counts and IDs, streamed one entry
// at a time — instead of decoding the whole archive into records (2026-09-26).
// Pinned here: the preview equals, field for field, the old preview (the whole
// payload decoded, then the old analyzer, kept verbatim) in both modes, against
// a store holding all, none or part of the backup; for archives with a row
// that does not decode, an entity this version does not know, and entities
// written twice; the same errors for a broken archive; and the decode runs off
// the main thread. Since 2026-11-02 the numbers differ from the old ones only
// where the restore changed (`expectSameAsOld`): a Merge counts every type and
// keeps a record changed since the backup (#1, #22), and a Replace updates the
// classroom share's records in place and leaves a type whose entry didn't
// decode (#2, #10).
@Suite("Backup restore preview digest")
@MainActor
struct BackupPreviewDigestTests {
    private typealias Fixtures = BackupStreamingFixtures

    /// A backup of every type (notes, attendance and check-ins past one fetch
    /// batch) plus two lesson assignments the merge analysis treats specially:
    /// one whose lesson is in neither the backup nor the library (inserted,
    /// with a warning) and one whose lessonID is not a UUID (skipped).
    private static func makeBackup() async throws -> (store: Fixtures.Store, url: URL) {
        let store = try Fixtures.makeStore()
        try Fixtures.seedEveryType(in: store.context)
        for lessonID in [UUID().uuidString, "not-a-uuid"] {
            let assignment = NSEntityDescription.insertNewObject(forEntityName: "LessonAssignment", into: store.context)
            assignment.setValue(UUID(), forKey: "id")
            assignment.setValue(lessonID, forKey: "lessonID")
        }
        try store.context.save()
        let url = store.archiveURL("Source")
        _ = try await BackupWriter.write(viewContext: store.context, to: url)
        return (store, url)
    }

    /// The preview as it was: decode everything, then the old analyzer.
    private static func legacyPreview(
        of url: URL,
        into context: NSManagedObjectContext,
        mode: BackupService.RestoreMode
    ) async throws -> RestorePreview {
        let archive = try await BackupImporter.decodeArchive(at: url)
        let idIndex = EntityIDIndexCache(context: context)
        let analysis = LegacyBackupPreviewAnalyzer.analyze(
            payload: archive.payload,
            viewContext: context,
            mode: mode,
            entityExists: { type, id in idIndex.exists(type, id: id) }
        )
        var preview = RestorePreview(
            mode: mode.rawValue,
            entityInserts: analysis.inserts,
            entitySkips: analysis.skips,
            entityDeletes: analysis.deletes,
            totalInserts: analysis.totalInserts,
            totalDeletes: analysis.totalDeletes,
            warnings: analysis.warnings + archive.warnings
        )
        // Since 2026-10-05 a Replace leaves this device's pin and the mirrored
        // Apple reminders and events as they are, and its preview no longer
        // counts them; the old analyzer still did.
        if mode == .replace {
            for kept in BackupEntityRegistry.keptOnRestoreEntityNames {
                preview.totalInserts -= preview.entityInserts.removeValue(forKey: kept) ?? 0
                preview.totalDeletes -= preview.entityDeletes.removeValue(forKey: kept) ?? 0
                preview.entitySkips.removeValue(forKey: kept)
            }
            // Since 2026-10-29 a Replace updates the names people set in
            // place, and its preview counts none of them as removed.
            for merged in BackupEntityRegistry.mergedOnReplaceEntityNames {
                preview.totalDeletes -= preview.entityDeletes[merged] ?? 0
                preview.entityDeletes[merged] = 0
            }
        }
        return preview
    }

    private static func preview(
        of url: URL,
        into context: NSManagedObjectContext,
        mode: BackupService.RestoreMode
    ) async throws -> RestorePreview {
        let coordinator = BackupCoordinator(
            backupService: BackupService(),
            transactionManager: BackupTransactionManager(),
            appRouter: AppRouter()
        )
        return try await coordinator.previewImport(viewContext: context, from: url, mode: mode, progress: { _, _ in })
    }

    private static func expectSamePreview(
        of url: URL,
        into context: NSManagedObjectContext,
        _ situation: String
    ) async throws {
        for mode in BackupService.RestoreMode.allCases {
            let old = try await legacyPreview(of: url, into: context, mode: mode)
            let new = try await preview(of: url, into: context, mode: mode)
            // The analysis the preview shows, with the records it keeps.
            let archive = try await BackupImporter.decodePreview(at: url)
            let index = EntityIDIndexCache(context: context)
            let analysis = BackupPreviewAnalyzer.analyze(
                digest: archive.digest, viewContext: context, mode: mode,
                formatVersion: archive.manifest.formatVersion, entityExists: { index.exists($0, id: $1) }
            )
            let label = "\(situation), \(mode.rawValue)"
            #expect(new.entityInserts == analysis.inserts, "\(label): the preview shows the analysis")
            #expect(new.entitySkips == analysis.skips, "\(label)")
            #expect(new.entityDeletes == analysis.deletes, "\(label)")
            #expect(new.entityKept == analysis.kept, "\(label): the preview passes on what it keeps")
            #expect(new.warnings == old.warnings, "\(label): warnings")
            expectSameAsOld(analysis, old, digest: archive.digest, mode: mode, label)
            let skips = new.entitySkips.values.reduce(0, +)
            let numbers = new.totalInserts + skips + new.totalDeletes
            #expect(numbers > 0, "\(label): a preview with numbers to compare")
        }
    }

    /// The new numbers against the old preview's, where the restore is the
    /// same: equal; where it changed on 2026-11-02, what the old numbers
    /// become. A Merge splits the old "already here" into updated and kept,
    /// and doesn't count a planned lesson it drops for a lessonID that isn't
    /// an id. A Replace updates a classroom-share record the backup holds in
    /// place (old: removed and added), and leaves a type whose entry didn't
    /// decode (old: all removed).
    private static func expectSameAsOld(
        _ new: BackupPreviewAnalyzer.AnalysisResult,
        _ old: RestorePreview,
        digest: BackupPreviewDigest,
        mode: BackupService.RestoreMode,
        _ label: String
    ) {
        for key in Set(old.entityInserts.keys).union(old.entityDeletes.keys).sorted() {
            let oldIns = old.entityInserts[key] ?? 0
            let oldSk = old.entitySkips[key] ?? 0
            let oldDel = old.entityDeletes[key] ?? 0
            let (ins, sk) = (new.inserts[key] ?? 0, new.skips[key] ?? 0)
            let (del, kept) = (new.deletes[key] ?? 0, new.kept[key] ?? 0)
            let archiveName = key == "WorkParticipant" ? "WorkParticipantEntity" : key
            if mode == .merge {
                let dropped = key == "LessonAssignment"
                    ? digest.lessonAssignments.filter { UUID(uuidString: $0.lessonID) == nil }.count : 0
                #expect(ins == oldIns, "\(label): \(key) added")
                #expect(sk + kept + dropped == oldSk, "\(label): \(key) already here")
                #expect(del == 0 && oldDel == 0, "\(label): \(key) removed")
            } else if digest.skippedEntityNames.contains(archiveName) {
                #expect(new.inserts[key] == nil && new.deletes[key] == nil, "\(label): \(key) left as it is")
            } else if BackupEntityRegistry.updatedInPlaceOnReplaceEntityNames.contains(key) {
                #expect(ins + sk == oldIns, "\(label): \(key) added or updated")
                #expect(del + sk == oldDel, "\(label): \(key) removed or updated")
            } else if BackupEntityRegistry.mergedOnReplaceEntityNames.contains(key) {
                #expect(ins + sk + kept == oldIns, "\(label): \(key)")
                #expect(del == 0 && oldDel == 0, "\(label): \(key) never removed")
            } else {
                #expect(ins == oldIns && sk == oldSk && del == oldDel, "\(label): \(key)")
            }
        }
    }

    // MARK: - Same numbers

    @Test("Against the store that made the backup: every record already there")
    func previewOfTheSameStore() async throws {
        let (store, url) = try await Self.makeBackup()
        defer { store.remove() }
        try await Self.expectSamePreview(of: url, into: store.context, "same store")
    }

    @Test("Against an empty store: every record new")
    func previewOfAnEmptyStore() async throws {
        let (store, url) = try await Self.makeBackup()
        defer { store.remove() }
        try await Self.expectSamePreview(of: url, into: try CoreDataTestHelpers.makeContext(), "empty store")
    }

    @Test("Against a store holding part of the backup")
    func previewOfAPartlyMatchingStore() async throws {
        let (store, url) = try await Self.makeBackup()
        defer { store.remove() }
        let payload = try await BackupImporter.decodeArchive(at: url).payload
        let context = try CoreDataTestHelpers.makeContext()
        // Some of every merge-checked kind already present, by ID.
        let present: [(entity: String, ids: [UUID])] = [
            ("Student", payload.students.map(\.id)),
            ("Lesson", payload.lessons.map(\.id)),
            ("Note", Array(payload.notes.map(\.id).prefix(400))),
            ("AttendanceRecord", Array(payload.attendance.map(\.id).suffix(250))),
            ("LessonAssignment", Array(payload.lessonAssignments.map(\.id).prefix(1)))
        ]
        for (entity, ids) in present {
            for id in ids {
                NSEntityDescription.insertNewObject(forEntityName: entity, into: context).setValue(id, forKey: "id")
            }
        }
        try context.save()
        try await Self.expectSamePreview(of: url, into: context, "partly matching store")
    }

    @Test("The digest streamed from an archive equals the digest of its decoded payload")
    func streamedDigestMatchesPayloadDigest() async throws {
        let (store, url) = try await Self.makeBackup()
        defer { store.remove() }
        let whole = try await BackupImporter.decodeArchive(at: url)
        let streamed = try await BackupImporter.decodePreview(at: url)
        #expect(streamed.digest == BackupPreviewDigest(payload: whole.payload))
        #expect(streamed.warnings == whole.warnings)
        #expect(streamed.manifest == whole.manifest)
        #expect(streamed.digest.count("Note") == 1_206)
        #expect(streamed.digest.lessonAssignments.count == 3)
    }

    // MARK: - Broken archives

    /// Writes `entries` as an encrypted archive with the app's key.
    private static func writeArchive(_ entries: [(path: String, data: Data)], to url: URL) throws {
        let key = try BackupEncryptionKeyStore.fetchOrCreateKey()
        try BackupArchive.write(to: url, encryptionKey: key) { appender in
            for entry in entries {
                try appender.append(path: entry.path, data: entry.data)
            }
        }
    }

    private static func path(_ entityName: String) -> String {
        "\(BackupWriter.store(for: entityName))/\(entityName).ndjson"
    }

    @Test("Skipped and repeated entries give the old numbers and the old warnings")
    func malformedEntriesMatchOldPreview() async throws {
        let (store, url) = try await Self.makeBackup()
        defer { store.remove() }
        let source = try Fixtures.contents(of: url)
        var entries: [(path: String, data: Data)] = []
        for path in source.paths {
            let body = try #require(source.bodies[path])
            switch path {
            case Self.path("Student"):
                // A row that does not decode: the whole type is skipped.
                entries.append((path, body + Data("{\"id\":5}\n".utf8)))
            case Self.path("Lesson"):
                // Written twice: the second entry, one row doubled, wins.
                entries.append((path, body))
                entries.append((path, body + body))
            case Self.path("Note"):
                // Written twice: the second does not decode, so the first stands.
                entries.append((path, body))
                entries.append((path, Data("not json\n".utf8)))
            default:
                entries.append((path, body))
            }
        }
        entries.append(("private/Mystery.ndjson", Data("{\"id\":\"x\"}\n".utf8)))
        let broken = store.archiveURL("Broken")
        try Self.writeArchive(entries, to: broken)

        try await Self.expectSamePreview(of: broken, into: store.context, "broken archive")
        let preview = try await Self.preview(of: broken, into: store.context, mode: .merge)
        #expect(preview.warnings.contains { $0.hasPrefix("Student records could not be read") })
        #expect(preview.warnings.contains { $0.hasPrefix("Note records could not be read") })
        #expect(preview.warnings.contains { $0.hasPrefix("Unknown entity 'Mystery'") })
        #expect(preview.entitySkips["Lesson"] == 2)
        #expect(preview.entitySkips["Note"] == 1_206)
    }

    @Test("An archive with no manifest, or a bad entry path, fails exactly as before")
    func brokenArchivesThrowTheOldErrors() async throws {
        let (store, url) = try await Self.makeBackup()
        defer { store.remove() }
        let source = try Fixtures.contents(of: url)
        let noManifest = store.archiveURL("NoManifest")
        try Self.writeArchive(
            source.paths.filter { $0 != "manifest.json" }.map { ($0, source.bodies[$0] ?? Data()) },
            to: noManifest
        )
        let badPath = store.archiveURL("BadPath")
        try Self.writeArchive(
            source.paths.map { ($0, source.bodies[$0] ?? Data()) } + [("loose.ndjson", Data("{}\n".utf8))],
            to: badPath
        )

        for broken in [noManifest, badPath] {
            var oldError: String?
            var newError: String?
            do { _ = try await Self.legacyPreview(of: broken, into: store.context, mode: .merge) } catch {
                oldError = error.localizedDescription
            }
            do { _ = try await Self.preview(of: broken, into: store.context, mode: .merge) } catch {
                newError = error.localizedDescription
            }
            #expect(oldError != nil)
            #expect(newError == oldError, "\(broken.lastPathComponent)")
        }
    }

    // MARK: - Threads

    @Test("The preview decode runs off the main thread")
    func previewDecodeRunsOffMain() async throws {
        let (store, url) = try await Self.makeBackup()
        defer { store.remove() }
        let recorder = BackupPipelineRecorder()
        _ = try await BackupPipelineRecorder.$current.withValue(recorder) {
            try await BackupImporter.decodePreview(at: url)
        }
        #expect(recorder.reached == [BackupPipelineRecorder.Step(phase: "decode preview", onMainThread: false)])
    }
}
