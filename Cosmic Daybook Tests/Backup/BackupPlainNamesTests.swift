import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What the restore preview and the restore summary show: every backed-up type under a
/// plain noun (`BackupPlainNames`), and every warning a restore or its preview writes in
/// plain words (`BackupWarningText`). The warnings themselves stay as written, for the
/// equivalence tests; the raw lines go under Details.
@Suite("Backup plain names and warnings")
@MainActor
struct BackupPlainNamesTests {
    private typealias Restore = BackupRestoreFixtures
    private typealias Fixtures = BackupStreamingFixtures

    // MARK: - Names

    @Test("Every backed-up type has a plain name")
    func everyBackedUpTypeHasAName() {
        let missing = BackupEntityTable.names.filter { BackupPlainNames.name(for: $0) == nil }
        #expect(missing.isEmpty, "no plain name for \(missing)")
    }

    @Test("Every type the restore preview lists has a plain name, in both modes")
    func everyPreviewTypeHasAName() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // Merge lists the types it compares one by one (18 today); replace, every backed-up type.
        for (mode, atLeast) in [(BackupService.RestoreMode.merge, 18), (.replace, 70)] {
            let analysis = BackupPreviewAnalyzer.analyze(
                digest: BackupPreviewDigest(), viewContext: context, mode: mode, entityExists: { _, _ in false }
            )
            let keys = Set(analysis.inserts.keys).union(analysis.skips.keys).union(analysis.deletes.keys)
            #expect(keys.count >= atLeast, "\(mode): \(keys.count) types")
            let missing = keys.filter { BackupPlainNames.name(for: $0) == nil }.sorted()
            #expect(missing.isEmpty, "\(mode): no plain name for \(missing)")
        }
    }

    @Test("A plain name is words, never a type name")
    func namesAreWords() {
        for entity in BackupEntityTable.names {
            let noun = BackupPlainNames.noun(for: entity)
            let camelCase = noun.range(of: "[a-z][A-Z]", options: .regularExpression)
            #expect(camelCase == nil, "\(entity) reads as \"\(noun)\"")
            #expect(!noun.contains("Entity") && !noun.hasPrefix("CD"), "\(entity) reads as \"\(noun)\"")
        }
    }

    @Test("The Core Data dressing comes off before the lookup; an unknown type is other items")
    func namesNormalize() {
        #expect(BackupPlainNames.noun(for: "CDCommunityTopicEntity") == "Community meeting topics")
        #expect(BackupPlainNames.noun(for: "WorkParticipantEntity") == "Children on work")
        #expect(BackupPlainNames.noun(for: "WorkParticipant") == "Children on work")
        #expect(BackupPlainNames.noun(for: "LessonAssignment") == "Planned lessons")
        #expect(BackupPlainNames.noun(for: "Mystery") == BackupPlainNames.fallback)
    }

    @Test("Counts of types that share a plain name are added together")
    func countsGroupByName() {
        let grouped = BackupPlainNames.grouped([
            "ProjectTemplateWeek": 2, "ProjectWeekRoleAssignment": 3, "Student": 1, "Mystery": 4, "Riddle": 1
        ])
        #expect(grouped == ["Old project plans": 5, "Students": 1, BackupPlainNames.fallback: 5])
    }

    // MARK: - Warnings

    @Test("Every warning a broken backup's restore writes has its own plain sentence")
    func brokenArchiveWarningsArePlain() async throws {
        let (store, url) = try await Restore.makeBackup(bulk: 0)
        defer { store.remove() }
        let broken = store.archiveURL("Broken")
        try Restore.writeArchive(try Restore.brokenEntries(from: try Fixtures.contents(of: url)), to: broken)

        let raw = try await Restore.restore(broken, into: CoreDataTestHelpers.makeContext(), mode: .merge)
            .summary.warnings
        #expect(raw.count >= 4, "\(raw)")
        for warning in raw {
            #expect(BackupWarningText.plain(warning) != BackupWarningText.fallback, "untranslated: \(warning)")
        }
        let plain = BackupWarningText.plain(raw)
        #expect(plain.contains("Part of this backup was damaged and was skipped (students)."))
        #expect(plain.contains("Part of this backup was damaged and was skipped (notes)."))
        #expect(plain.contains(
            "Part of this backup was made by a newer version of the app and was skipped. "
                + "Update Cosmic Daybook to restore all of it."
        ))
        // Two unknown types read as one sentence, said once.
        #expect(plain.count == Set(plain).count)
        // The raw lines, decode errors and all, are kept for Details (all but the album
        // reattach warning, which is plain already).
        let details = BackupWarningText.details(raw)
        let translated = raw.filter { BackupWarningText.plain($0) != $0 }
        #expect(translated.count >= 4)
        #expect(translated.allSatisfy { details.contains($0) })
    }

    @Test("The restore's own warnings, and the preview's, read plainly")
    func restoreWarningsArePlain() {
        let cases: [(raw: String, plain: String)] = [
            (
                "iCloud sync reported a failure: CKErrorDomain 2 (partial failure). "
                    + "Your data is saved locally; check Settings → iCloud to retry.",
                "Your restored notebook is saved on this device but hasn't reached iCloud yet. It'll keep trying."
            ),
            (
                "iCloud sync is still running in the background. Keep the app open for a moment to finish uploading.",
                "Your restored notebook is still going up to iCloud. Keep the app open for a moment so it can finish."
            ),
            (
                "1 lesson assignments reference lessons missing from both this backup and the library; "
                    + "they will be restored but stay unlinked until their lesson exists.",
                "1 planned lesson points to a lesson that isn't in this backup or your notebook. "
                    + "It'll reconnect once that lesson is added."
            ),
            (
                "12 lesson assignments reference lessons missing from both this backup and the library; "
                    + "they will be restored but stay unlinked until their lesson exists.",
                "12 planned lessons point to lessons that aren't in this backup or your notebook. "
                    + "They'll reconnect once those lessons are added."
            ),
            ("3 note photo(s) could not be restored.", "3 note photos couldn't be restored."),
            ("1 note photo(s) could not be restored.", "1 note photo couldn't be restored.")
        ]
        for (raw, plain) in cases {
            #expect(BackupWarningText.plain(raw) == plain)
        }
        let album = "This backup includes bookmarks, notes, highlights, or drawings for 2 albums. "
            + "Open Albums and add your album folder to reattach them."
        #expect(BackupWarningText.plain(album) == album)
        #expect(BackupWarningText.plain("Something new went sideways: 0xDEAD") == BackupWarningText.fallback)
    }

    @Test("Details holds only the lines that read differently on screen")
    func detailsSkipsPlainLines() {
        let album = "This backup includes bookmarks, notes, highlights, or drawings for 1 album. "
            + "Open Albums and add your album folder to reattach it."
        let photos = "2 note photo(s) could not be restored."
        #expect(BackupWarningText.details([album]).isEmpty)
        #expect(BackupWarningText.details([album, photos]) == photos)
    }

    // MARK: - The finished backup's note

    @Test("A finished backup's photo note is information, in plain words")
    func photoNote() {
        #expect(BackupWriter.photoNote(includesPhotos: true, photoCount: 1)
            == "Includes 1 note photo. Imported documents and file attachments aren't in backups.")
        #expect(BackupWriter.photoNote(includesPhotos: true, photoCount: 12)
            == "Includes 12 note photos. Imported documents and file attachments aren't in backups.")
        #expect(BackupWriter.photoNote(includesPhotos: false, photoCount: 0)
            == "Note photos, imported documents and file attachments aren't in this backup.")
    }
}
