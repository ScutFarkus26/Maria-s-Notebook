import CoreData
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CosmicDaybook

/// Lesson file attachments, Phase 1: the one writer of a lesson's files. Each
/// test works in a scratch iCloud container of its own (the Lesson Files
/// folder inside it), an in-memory store, and a stand-in Trash that moves
/// files aside instead of deleting them, so "went to the Trash" can be checked.
@Suite("Lesson files: LessonAttachmentService")
@MainActor
struct LessonAttachmentServiceTests {

    // MARK: - Adding

    @Test("Add copies the file in and keeps the title as given; only the name on disk is sanitized")
    func addKeepsTheTitle() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let bytes = Self.pdf()
        let source = try scratch.write(bytes, named: "circle-area-of-a-circle.pdf")

        let attachment = try scratch.service().add(
            fileAt: source, to: scratch.lesson, title: "  Area of a Circle — remade album pages ",
            notes: "From the remade Geometry album", allowedTypes: LessonAttachmentService.pdfOrImage
        )

        #expect(attachment.fileName == "Area of a Circle — remade album pages.pdf")
        #expect(attachment.title == "Area of a Circle — remade album pages")
        #expect(attachment.fileRelativePath == "Geometry/Circle/Area of a Circle - remade album pages.pdf")
        #expect(try Data(contentsOf: scratch.file(of: attachment)) == bytes)
        #expect(FileManager.default.fileExists(atPath: source.path), "the original stays where it was")
        #expect(attachment.fileType == "pdf")
        #expect(attachment.fileSizeBytes == Int64(bytes.count))
        #expect(attachment.scope == .lesson)
        #expect(attachment.notes == "From the remade Geometry album")
        #expect(attachment.lesson == scratch.lesson)
        #expect(attachment.fileBookmark != nil)
        #expect(attachment.id != nil)
        let attachedAt = try #require(attachment.attachedAt)
        #expect(attachment.modifiedAt == attachedAt)
        #expect(attachment.lastChanged == attachedAt)
        #expect(!scratch.context.hasChanges, "the add saves")
        #expect(try scratch.persisted(attachment.id)?.path == attachment.fileRelativePath)
    }

    @Test("Without a title the file keeps its own name, as the Files card always did")
    func addWithoutATitle() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let source = try scratch.write(Self.png(), named: "Bead Chart.png")

        let attachment = try scratch.service().add(
            fileAt: source, to: scratch.lesson, scope: .sequence, allowedTypes: LessonAttachmentService.anyFile
        )

        #expect(attachment.fileName == "Bead Chart.png")
        #expect(attachment.title == "Bead Chart")
        #expect(attachment.fileType == "png")
        #expect(attachment.scope == .sequence)
        #expect(attachment.fileRelativePath == "Geometry/Circle/[Sequence] Bead Chart.png")
    }

    @Test("A failed save leaves no record and no copy behind")
    func addWhoseSaveFails() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let source = try scratch.write(Self.pdf(), named: "Circle.pdf")
        let service = scratch.service(save: { _ in throw SaveRefused() })

        #expect(throws: LessonAttachmentService.Problem.saveFailed) {
            try service.add(fileAt: source, to: scratch.lesson, allowedTypes: LessonAttachmentService.pdfOrImage)
        }
        #expect(try scratch.lessonFolderNames().isEmpty)
        #expect((scratch.lesson.attachments?.count ?? 0) == 0)
        // A later save of something else doesn't carry the record with it.
        try scratch.context.save()
        #expect(try scratch.context.count(for: CDFetchRequest(CDLessonAttachment.self)) == 0)
    }

    // MARK: - Replacing

    @Test("Replace keeps the record and gives it a new copy; the old file goes to the Trash after the save")
    func replaceSwapsTheFile() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let oldBytes = Self.pdf()
        let newBytes = Self.pdf(size: CGSize(width: 1224, height: 1584), shade: 0.2)
        try #require(oldBytes.count != newBytes.count)
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(oldBytes, named: "circle.pdf"), to: scratch.lesson,
            title: "Area of a Circle", allowedTypes: LessonAttachmentService.pdfOrImage
        )
        attachment.modifiedAt = Self.earlier
        attachment.thumbnailData = Data([1, 2, 3])
        try scratch.context.save()
        let id = attachment.id
        let oldPath = attachment.fileRelativePath
        let oldBookmark = attachment.fileBookmark
        let oldURL = try scratch.file(of: attachment)

        let source = try scratch.write(newBytes, named: "circle-v2.pdf")
        let outcome = try await scratch.service().replace(
            attachment, withFileAt: source, notes: "Remade 2026-10-26", allowedTypes: LessonAttachmentService.pdfOrImage
        )

        #expect(outcome == .replaced)
        #expect(attachment.id == id)
        #expect(attachment.fileRelativePath != oldPath)
        #expect(attachment.fileRelativePath == "Geometry/Circle/Area of a Circle-2.pdf")
        let newBookmark = try #require(attachment.fileBookmark)
        #expect(newBookmark != oldBookmark)
        #expect(try Data(contentsOf: scratch.file(of: attachment)) == newBytes)
        #expect(attachment.fileSizeBytes == Int64(newBytes.count))
        let modifiedAt = try #require(attachment.modifiedAt)
        #expect(modifiedAt > Self.earlier)
        #expect(attachment.thumbnailData == nil)
        #expect(attachment.notes == "Remade 2026-10-26")
        #expect(attachment.fileName == "Area of a Circle.pdf")
        #expect(!scratch.context.hasChanges)
        #expect(try scratch.persisted(id)?.path == attachment.fileRelativePath)
        #expect((scratch.lesson.attachments?.count ?? 0) == 1, "still one attachment")

        // The old file went to the Trash, not away.
        try scratch.expectOnlyTrashed(oldURL, holding: oldBytes)
    }

    @Test("A replace never deletes first: at its save both the old file and the new copy are on disk")
    func replaceSavesBeforeTrashing() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let oldURL = try scratch.file(of: attachment)
        var onDiskAtSave: [Bool] = []
        var trashedAtSave: [URL] = []
        let service = scratch.service(save: { context in
            let newURL = try scratch.storage.resolve(relativePath: attachment.fileRelativePath)
            onDiskAtSave = [oldURL, newURL].map { FileManager.default.fileExists(atPath: $0.path) }
            trashedAtSave = scratch.trash.given
            try context.save()
        })

        _ = try await service.replace(
            attachment, withFileAt: try scratch.write(Self.pdf(shade: 0.9), named: "new.pdf"),
            allowedTypes: LessonAttachmentService.pdfOrImage
        )

        #expect(onDiskAtSave == [true, true])
        #expect(trashedAtSave.isEmpty)
        #expect(scratch.trash.given.count == 1)
    }

    @Test("Replacing with the same bytes and the same note writes nothing; a new note alone is saved")
    func replaceWithTheSameFile() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let bytes = Self.pdf()
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(bytes, named: "circle.pdf"), to: scratch.lesson,
            notes: "From the album", allowedTypes: LessonAttachmentService.pdfOrImage
        )
        attachment.modifiedAt = Self.earlier
        try scratch.context.save()
        let path = attachment.fileRelativePath
        var saves = 0
        let service = scratch.service(save: { context in
            saves += 1
            try context.save()
        })
        let sameBytes = try scratch.write(bytes, named: "circle copy.pdf")

        let unchanged = try await service.replace(
            attachment, withFileAt: sameBytes, notes: "From the album", allowedTypes: LessonAttachmentService.pdfOrImage
        )
        #expect(unchanged == .unchanged)
        #expect(saves == 0)
        #expect(!scratch.context.hasChanges)
        #expect(attachment.modifiedAt == Self.earlier)
        #expect(attachment.fileRelativePath == path)
        #expect(try scratch.lessonFolderNames() == ["circle.pdf"])
        #expect(scratch.trash.given.isEmpty)

        let withoutNote = try await service.replace(
            attachment, withFileAt: sameBytes, allowedTypes: LessonAttachmentService.pdfOrImage
        )
        #expect(withoutNote == .unchanged, "no note given keeps the note")

        let noteOnly = try await service.replace(
            attachment, withFileAt: sameBytes, notes: "From the remake",
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        #expect(noteOnly == .noteChanged)
        #expect(saves == 1)
        #expect(attachment.notes == "From the remake")
        #expect(try #require(attachment.modifiedAt) > Self.earlier)
        #expect(attachment.fileRelativePath == path)
        #expect(try scratch.lessonFolderNames() == ["circle.pdf"])
        #expect(scratch.trash.given.isEmpty)
    }

    @Test("A replace whose save fails leaves the old file and record as they were, with no stray copy")
    func replaceWhoseSaveFails() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let oldBytes = Self.pdf()
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(oldBytes, named: "circle.pdf"), to: scratch.lesson,
            notes: "Old note", allowedTypes: LessonAttachmentService.pdfOrImage
        )
        attachment.modifiedAt = Self.earlier
        try scratch.context.save()
        let path = attachment.fileRelativePath
        let size = attachment.fileSizeBytes
        let bookmark = attachment.fileBookmark
        let oldURL = try scratch.file(of: attachment)
        let failing = scratch.service(save: { _ in throw SaveRefused() })
        let source = try scratch.write(Self.png(), named: "circle.png")

        await #expect(throws: LessonAttachmentService.Problem.saveFailed) {
            try await failing.replace(
                attachment, withFileAt: source, notes: "New note", allowedTypes: LessonAttachmentService.pdfOrImage
            )
        }

        #expect(attachment.fileRelativePath == path)
        #expect(attachment.fileSizeBytes == size)
        #expect(attachment.fileBookmark == bookmark)
        #expect(attachment.fileType == "pdf")
        #expect(attachment.fileName == "circle.pdf")
        #expect(attachment.notes == "Old note")
        #expect(attachment.modifiedAt == Self.earlier)
        #expect(try Data(contentsOf: oldURL) == oldBytes)
        #expect(try scratch.lessonFolderNames() == ["circle.pdf"], "the new copy was removed")
        #expect(scratch.trash.given.isEmpty)
        // A later save of something else doesn't carry the replace with it.
        scratch.lesson.name = "Area of a Circle (revised)"
        try scratch.context.save()
        let stored = try #require(try scratch.persisted(attachment.id))
        #expect(stored.path == path)
        #expect(stored.size == size)
        #expect(stored.modifiedAt == Self.earlier)
        #expect(stored.notes == "Old note")
    }

    @Test("A replace goes ahead when the old file is missing, and the copy still gets a new name")
    func replaceWhenTheOldFileIsMissing() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let oldPath = attachment.fileRelativePath
        try FileManager.default.removeItem(at: scratch.file(of: attachment))
        let newBytes = Self.pdf(shade: 0.1)

        let outcome = try await scratch.service().replace(
            attachment, withFileAt: try scratch.write(newBytes, named: "new.pdf"),
            allowedTypes: LessonAttachmentService.pdfOrImage
        )

        #expect(outcome == .replaced)
        #expect(attachment.fileRelativePath != oldPath, "the record's old name is held, as for a file not here yet")
        #expect(try Data(contentsOf: scratch.file(of: attachment)) == newBytes)
        #expect(scratch.trash.contents.isEmpty, "nothing was there to move")
    }

    @Test("Replacing a PDF with a PNG changes the type and the name's extension, and keeps the title")
    func replacePDFWithPNG() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            title: "Area of a Circle — chart", allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let pngBytes = Self.png()

        let outcome = try await scratch.service().replace(
            attachment, withFileAt: try scratch.write(pngBytes, named: "chart.png"),
            allowedTypes: LessonAttachmentService.pdfOrImage
        )

        #expect(outcome == .replaced)
        #expect(attachment.fileType == "png")
        #expect(attachment.fileName == "Area of a Circle — chart.png")
        #expect(attachment.title == "Area of a Circle — chart")
        #expect(attachment.fileRelativePath == "Geometry/Circle/Area of a Circle - chart.png")
        #expect(try Data(contentsOf: scratch.file(of: attachment)) == pngBytes)
        #expect(scratch.trash.given.count == 1)
    }
}
