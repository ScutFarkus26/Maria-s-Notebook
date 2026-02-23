#if canImport(Testing)
import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Maria_s_Notebook

/// Tests for Modal/Sheet view data layer.
/// Note: Full visual snapshot testing requires the SnapshotTesting library.
/// These tests verify the data models are correctly configured for modal display.
@Suite("Modal Views Data Tests")
struct ModalViewsSnapshotTests {

    // MARK: - Note Tests

    @Test("Note edit sheet data")
    @MainActor
    func noteEditSheet_data() throws {
        let container = try makeSnapshotTestContainer()
        let note = SnapshotTestData.makeNote(
            body: "This is an existing note that we're editing.",
            scope: .all,
            isPinned: false
        )
        container.mainContext.insert(note)
        try container.mainContext.save()

        #expect(note.body.contains("existing note"))
        #expect(!note.isPinned)
        #expect(note.scope == .all)
    }

    @Test("Note pinned data")
    @MainActor
    func noteEditSheet_pinnedNote() throws {
        let container = try makeSnapshotTestContainer()
        let note = SnapshotTestData.makeNote(
            body: "This is a pinned note with important information.",
            scope: .all,
            isPinned: true
        )
        container.mainContext.insert(note)
        try container.mainContext.save()

        #expect(note.isPinned)
    }

    // MARK: - Backup Summary Tests

    @Test("Backup summary export data")
    func backupSummary_exportData() {
        let summary = BackupOperationSummary(
            kind: .export,
            fileName: "test_backup.mtbbackup",
            formatVersion: BackupFile.formatVersion,
            encryptUsed: false,
            createdAt: SnapshotDates.reference,
            entityCounts: [
                "Student": 25,
                "Lesson": 150,
                "StudentLesson": 500,
                "Note": 1200,
                "AttendanceRecord": 3000,
                "WorkModel": 450
            ],
            warnings: []
        )

        #expect(summary.kind == .export)
        #expect(summary.fileName == "test_backup.mtbbackup")
        #expect(!summary.encryptUsed)
        #expect(summary.warnings.isEmpty)
        #expect(summary.entityCounts["Student"] == 25)
    }

    @Test("Backup summary import data")
    func backupSummary_importData() {
        let summary = BackupOperationSummary(
            kind: .import,
            fileName: "imported_backup.mtbbackup",
            formatVersion: BackupFile.formatVersion,
            encryptUsed: true,
            createdAt: SnapshotDates.reference,
            entityCounts: [
                "Student": 25,
                "Lesson": 150,
                "Note": 1200
            ],
            warnings: []
        )

        #expect(summary.kind == .import)
        #expect(summary.encryptUsed)
    }

    @Test("Backup summary with warnings")
    func backupSummary_withWarnings() {
        let summary = BackupOperationSummary(
            kind: .export,
            fileName: "backup_with_warnings.mtbbackup",
            formatVersion: BackupFile.formatVersion,
            encryptUsed: false,
            createdAt: SnapshotDates.reference,
            entityCounts: [
                "Student": 25,
                "Lesson": 150
            ],
            warnings: [
                "Files/attachments are not included in backups by design.",
                "Some lessons reference missing students",
                "3 notes have invalid dates"
            ]
        )

        #expect(summary.warnings.count == 3)
        #expect(summary.warnings.contains { $0.contains("Files/attachments") })
    }

    @Test("Backup summary encrypted")
    func backupSummary_encrypted() {
        let summary = BackupOperationSummary(
            kind: .export,
            fileName: "encrypted_backup.mtbbackup",
            formatVersion: BackupFile.formatVersion,
            encryptUsed: true,
            createdAt: SnapshotDates.reference,
            entityCounts: [
                "Student": 25,
                "Lesson": 150
            ],
            warnings: []
        )

        #expect(summary.encryptUsed)
        #expect(summary.fileName.contains("encrypted"))
    }

    // MARK: - Student Tests

    @Test("Student creation data")
    @MainActor
    func studentCreation_data() throws {
        let container = try makeSnapshotTestContainer()
        let student = SnapshotTestData.makeStudent()
        container.mainContext.insert(student)
        try container.mainContext.save()

        #expect(student.firstName == "Emma")
        #expect(student.lastName == "Johnson")
        #expect(student.level == .lower)
    }

    // MARK: - Lesson Tests

    @Test("Lesson creation data")
    @MainActor
    func lessonCreation_data() throws {
        let container = try makeSnapshotTestContainer()
        let lesson = SnapshotTestData.makeLesson()
        container.mainContext.insert(lesson)
        try container.mainContext.save()

        #expect(lesson.name == "Addition Facts")
        #expect(lesson.subject == "Math")
        #expect(lesson.group == "Operations")
    }
}

#endif
