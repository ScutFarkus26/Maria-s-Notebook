#if canImport(Testing)
import Testing
import Foundation
@testable import Maria_s_Notebook

/// Snapshot tests for backup JSON structures.
/// These tests verify the backup file format remains consistent across versions.
@Suite("Backup Manifest Snapshots")
struct BackupManifestSnapshotTests {

    // MARK: - Manifest Tests

    @Test("Manifest full content")
    func manifest_fullContent() throws {
        let manifest = SnapshotTestData.makeBackupManifest(
            entityCounts: [
                "AttendanceRecord": 3000,
                "Lesson": 150,
                "Note": 1200,
                "Student": 25,
                "StudentLesson": 500,
                "WorkModel": 450
            ],
            sha256: "abc123def456789...",
            notes: "Weekly backup",
            compression: "lzfse"
        )

        try assertJSONSnapshot(manifest, named: "fullContent")
    }

    @Test("Manifest minimal")
    func manifest_minimal() throws {
        let manifest = BackupManifest(
            entityCounts: ["Student": 10],
            sha256: "test_hash_minimal",
            notes: nil,
            compression: nil
        )

        try assertJSONSnapshot(manifest, named: "minimal")
    }

    @Test("Manifest with compression")
    func manifest_withCompression() throws {
        let manifest = BackupManifest(
            entityCounts: ["Student": 10, "Lesson": 50],
            sha256: "compressed_hash",
            notes: "Compressed backup",
            compression: BackupFile.compressionAlgorithm
        )

        try assertJSONSnapshot(manifest, named: "withCompression")
    }

    @Test("Manifest empty entity counts")
    func manifest_emptyEntityCounts() throws {
        let manifest = BackupManifest(
            entityCounts: [:],
            sha256: "empty_hash",
            notes: nil,
            compression: nil
        )

        try assertJSONSnapshot(manifest, named: "emptyEntityCounts")
    }

    // MARK: - Envelope Tests

    @Test("Envelope structure")
    func envelope_structure() throws {
        let envelope = SnapshotTestData.makeBackupEnvelope()

        try assertJSONSnapshot(envelope, named: "structure")
    }

    @Test("Envelope with all fields")
    func envelope_withAllFields() throws {
        let manifest = SnapshotTestData.makeBackupManifest(
            compression: BackupFile.compressionAlgorithm
        )

        let envelope = BackupEnvelope(
            formatVersion: BackupFile.formatVersion,
            createdAt: SnapshotDates.reference,
            appBuild: "150",
            appVersion: "2.1.0",
            device: "MacBook Pro M2",
            manifest: manifest,
            payload: nil,
            encryptedPayload: nil,
            compressedPayload: nil
        )

        try assertJSONSnapshot(envelope, named: "withAllFields")
    }

    // MARK: - Restore Preview Tests

    @Test("Restore preview merge mode")
    func restorePreview_mergeMode() throws {
        let preview = SnapshotTestData.makeRestorePreview(mode: "merge")

        try assertJSONSnapshot(preview, named: "mergeMode")
    }

    @Test("Restore preview replace mode")
    func restorePreview_replaceMode() throws {
        let preview = RestorePreview(
            mode: "replace",
            entityInserts: ["Student": 25, "Lesson": 150, "Note": 1200],
            entitySkips: [:],
            entityDeletes: ["Student": 20, "Lesson": 100, "Note": 800],
            totalInserts: 1375,
            totalDeletes: 920,
            warnings: []
        )

        try assertJSONSnapshot(preview, named: "replaceMode")
    }

    @Test("Restore preview with multiple warnings")
    func restorePreview_withMultipleWarnings() throws {
        let preview = RestorePreview(
            mode: "merge",
            entityInserts: ["Student": 5],
            entitySkips: ["Student": 20],
            entityDeletes: [:],
            totalInserts: 5,
            totalDeletes: 0,
            warnings: [
                "Some lessons reference missing students",
                "3 notes have invalid dates",
                "Work items may have orphaned references"
            ]
        )

        try assertJSONSnapshot(preview, named: "withMultipleWarnings")
    }

    @Test("Restore preview no changes")
    func restorePreview_noChanges() throws {
        let preview = RestorePreview(
            mode: "merge",
            entityInserts: [:],
            entitySkips: ["Student": 25, "Lesson": 150],
            entityDeletes: [:],
            totalInserts: 0,
            totalDeletes: 0,
            warnings: []
        )

        try assertJSONSnapshot(preview, named: "noChanges")
    }

    // MARK: - Backup Summary Tests

    @Test("Backup summary structure")
    func backupSummary_structure() throws {
        let summary = BackupSummary(
            totalCount: 5325,
            countsByEntity: [
                "Student": 25,
                "Lesson": 150,
                "StudentLesson": 500,
                "Note": 1200,
                "AttendanceRecord": 3000,
                "WorkModel": 450
            ]
        )

        try assertJSONSnapshot(summary, named: "structure")
    }

    // MARK: - Preferences DTO Tests

    @Test("Preferences DTO structure")
    func preferencesDTO_structure() throws {
        let prefs = PreferencesDTO(values: [
            "AttendanceEmail.enabled": .bool(true),
            "AttendanceEmail.to": .string("teacher@school.edu"),
            "theme.darkMode": .bool(false),
            "sync.lastDate": .date(SnapshotDates.reference),
            "view.defaultTab": .int(0),
            "display.scale": .double(1.5)
        ])

        try assertJSONSnapshot(prefs, named: "structure")
    }

    @Test("Preference value DTO all types")
    func preferenceValueDTO_allTypes() throws {
        let values: [String: PreferenceValueDTO] = [
            "boolValue": .bool(true),
            "intValue": .int(42),
            "doubleValue": .double(3.14),
            "stringValue": .string("test string"),
            "dataValue": .data(Data([0x48, 0x65, 0x6C, 0x6C, 0x6F])),
            "dateValue": .date(SnapshotDates.reference)
        ]

        let prefs = PreferencesDTO(values: values)
        try assertJSONSnapshot(prefs, named: "allTypes")
    }
}

#endif
