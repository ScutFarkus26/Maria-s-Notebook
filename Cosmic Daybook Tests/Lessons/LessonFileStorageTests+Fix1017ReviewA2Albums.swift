import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Review of the 2026-10-17 file fixes, part A (14): a lesson attachment's
/// name taken by another device's record whose file hasn't come down yet.
@Suite("Lesson files: names held by synced attachments (bug hunt 10-17, review A2)")
@MainActor
struct LessonFileStorageFix1017ReviewA2AlbumsTests {

    /// A lesson filed under an area of its own, its folder, and its context.
    private struct Setup {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let folder: URL

        init() throws {
            context = try CoreDataTestHelpers.makeContext()
            lesson = CDLesson(context: context)
            lesson.name = "Bead Chains"
            lesson.area = "Fix1017 A2 \(UUID().uuidString)"
            lesson.sequence = "Chains"
            folder = try LessonFileStorage.organizationalDirectory(forLesson: lesson)
        }

        /// The area's folder, removed after the test.
        var areaFolder: URL { folder.deletingLastPathComponent() }

        /// Another device's attachment record whose file hasn't arrived here:
        /// no file, and no iCloud placeholder either.
        @discardableResult
        func syncedRecord(named fileName: String) throws -> CDLessonAttachment {
            let attachment = CDLessonAttachment(context: context)
            attachment.lesson = lesson
            attachment.scope = .lesson
            attachment.fileName = fileName
            attachment.fileRelativePath = try LessonFileStorage.relativePath(
                forManagedURL: folder.appendingPathComponent(fileName)
            )
            return attachment
        }
    }

    @Test("Renaming an attachment skips a name another device's record holds before its file arrives")
    func renameSkipsANameHeldByARecord() throws {
        let setup = try Setup()
        defer { try? FileManager.default.removeItem(at: setup.areaFolder) }
        let file = setup.folder.appendingPathComponent("Notes.pdf")
        try Data("notes".utf8).write(to: file)
        let attachment = CDLessonAttachment(context: setup.context)
        attachment.lesson = setup.lesson
        attachment.scope = .lesson
        attachment.fileRelativePath = try LessonFileStorage.relativePath(forManagedURL: file)
        try setup.syncedRecord(named: "Chart.pdf")

        let renamed = try LessonFileStorage.renameAttachment(attachment, to: "Chart")

        #expect(renamed.url.lastPathComponent == "Chart-2.pdf")
        #expect(try Data(contentsOf: renamed.url) == Data("notes".utf8))
    }

    @Test("A name only differing in case from a record's is taken too")
    func renameTreatsCaseAsTheSameName() throws {
        let setup = try Setup()
        defer { try? FileManager.default.removeItem(at: setup.areaFolder) }
        let file = setup.folder.appendingPathComponent("Notes.pdf")
        try Data("notes".utf8).write(to: file)
        let attachment = CDLessonAttachment(context: setup.context)
        attachment.lesson = setup.lesson
        attachment.scope = .lesson
        attachment.fileRelativePath = try LessonFileStorage.relativePath(forManagedURL: file)
        try setup.syncedRecord(named: "chart.pdf")

        let renamed = try LessonFileStorage.renameAttachment(attachment, to: "Chart")

        #expect(renamed.url.lastPathComponent == "Chart-2.pdf")
    }

    @Test("Renaming an attachment to its own name leaves it where it is")
    func renameToItsOwnNameStays() throws {
        let setup = try Setup()
        defer { try? FileManager.default.removeItem(at: setup.areaFolder) }
        let file = setup.folder.appendingPathComponent("Notes.pdf")
        try Data("notes".utf8).write(to: file)
        let attachment = CDLessonAttachment(context: setup.context)
        attachment.lesson = setup.lesson
        attachment.scope = .lesson
        attachment.fileRelativePath = try LessonFileStorage.relativePath(forManagedURL: file)

        let renamed = try LessonFileStorage.renameAttachment(attachment, to: "Notes")

        #expect(renamed.url.lastPathComponent == "Notes.pdf")
        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("A new attachment skips a name another device's record holds before its file arrives")
    func importSkipsANameHeldByARecord() throws {
        let setup = try Setup()
        defer { try? FileManager.default.removeItem(at: setup.areaFolder) }
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fix1017A2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source) }
        let picked = source.appendingPathComponent("Notes.pdf")
        try Data("picked".utf8).write(to: picked)
        try setup.syncedRecord(named: "Notes.pdf")

        let imported = try LessonFileStorage.importAttachment(from: picked, forLesson: setup.lesson)

        #expect(imported.url.lastPathComponent == "Notes-2.pdf")
        #expect(try Data(contentsOf: imported.url) == Data("picked".utf8))
    }
}
