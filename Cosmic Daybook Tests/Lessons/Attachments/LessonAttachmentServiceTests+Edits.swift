import CoreData
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CosmicDaybook

/// Renaming, notes, removing, the Sample Class and finding by title.
extension LessonAttachmentServiceTests {
    // MARK: - Renaming and notes

    @Test("Rename keeps the typed name, sanitizes only the file, and bumps modifiedAt")
    func renameKeepsTheTypedName() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let service = scratch.service()
        let attachment = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        attachment.modifiedAt = Self.earlier
        try scratch.context.save()
        let oldURL = try scratch.file(of: attachment)

        #expect(try service.rename(attachment, to: " Circle — Chart "))

        #expect(attachment.fileName == "Circle — Chart.pdf")
        #expect(attachment.fileRelativePath == "Geometry/Circle/Circle - Chart.pdf")
        #expect(FileManager.default.fileExists(atPath: try scratch.file(of: attachment).path))
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(try #require(attachment.modifiedAt) > Self.earlier)
        #expect(!scratch.context.hasChanges)

        let before = attachment.modifiedAt
        #expect(try !service.rename(attachment, to: "Circle — Chart.pdf"), "the same name changes nothing")
        #expect(attachment.modifiedAt == before)
        #expect(throws: LessonAttachmentService.Problem.emptyName) {
            try service.rename(attachment, to: "   ")
        }
    }

    @Test("A rename whose save fails puts the file and the name back")
    func renameWhoseSaveFails() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let oldURL = try scratch.file(of: attachment)

        #expect(throws: LessonAttachmentService.Problem.saveFailed) {
            try scratch.service(save: { _ in throw SaveRefused() }).rename(attachment, to: "Chart")
        }
        #expect(attachment.fileName == "circle.pdf")
        #expect(attachment.fileRelativePath == "Geometry/Circle/circle.pdf")
        #expect(FileManager.default.fileExists(atPath: oldURL.path))
        #expect(try scratch.lessonFolderNames() == ["circle.pdf"])
    }

    @Test("Setting a note bumps modifiedAt; the same note writes nothing")
    func setNotes() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let service = scratch.service()
        let attachment = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        attachment.modifiedAt = Self.earlier
        try scratch.context.save()

        #expect(try service.setNotes(attachment, " From the remade album "))
        #expect(attachment.notes == "From the remade album")
        #expect(try #require(attachment.modifiedAt) > Self.earlier)
        #expect(try scratch.persisted(attachment.id)?.notes == "From the remade album")

        let before = attachment.modifiedAt
        #expect(try !service.setNotes(attachment, "From the remade album"))
        #expect(attachment.modifiedAt == before)
        #expect(!scratch.context.hasChanges)
    }

    // MARK: - Removing

    @Test("Remove deletes the record, clears primary, trashes the file, and keeps one another record uses")
    func removeTrashesOnlyUnusedFiles() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let service = scratch.service()
        let attachment = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let fileURL = try scratch.file(of: attachment)
        // A second record using the same file, on another lesson.
        let other = CoreDataTestHelpers.seedLesson(in: scratch.context, name: "Circumference")
        let sharer = CDLessonAttachment(context: scratch.context)
        sharer.fileName = "circle.pdf"
        sharer.fileRelativePath = attachment.fileRelativePath
        sharer.lesson = other
        scratch.lesson.primaryAttachmentID = attachment.id?.uuidString
        try scratch.context.save()
        let id = attachment.id

        try service.remove(attachment)

        #expect(scratch.lesson.primaryAttachmentID == nil)
        #expect(try scratch.persisted(id) == nil)
        #expect(!scratch.context.hasChanges)
        #expect(scratch.trash.given.isEmpty, "another record still uses the file")
        #expect(FileManager.default.fileExists(atPath: fileURL.path))

        try service.remove(sharer)

        #expect(scratch.trash.given.map(\.standardizedFileURL) == [fileURL.standardizedFileURL])
        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
        #expect(scratch.trash.contents.count == 1, "moved to the Trash, not deleted")
    }

    @Test("A remove whose save fails keeps the record, the primary mark and the file")
    func removeWhoseSaveFails() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        scratch.lesson.primaryAttachmentID = attachment.id?.uuidString
        try scratch.context.save()

        #expect(throws: LessonAttachmentService.Problem.saveFailed) {
            try scratch.service(save: { _ in throw SaveRefused() }).remove(attachment)
        }
        #expect(!attachment.isDeleted)
        #expect(scratch.lesson.primaryAttachmentID == attachment.id?.uuidString)
        #expect(scratch.trash.given.isEmpty)
        #expect(try scratch.lessonFolderNames() == ["circle.pdf"])
    }

    // MARK: - The Sample Class

    @Test("The Sample Class can't add or replace files; a rename or remove there changes the record only")
    func sampleClass() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let fileURL = try scratch.file(of: attachment)
        let sample = scratch.service(isSampleClassroom: true)
        let source = try scratch.write(Self.png(), named: "chart.png")

        #expect(throws: LessonAttachmentService.Problem.sampleClass) {
            try sample.add(fileAt: source, to: scratch.lesson, allowedTypes: LessonAttachmentService.pdfOrImage)
        }
        await #expect(throws: LessonAttachmentService.Problem.sampleClass) {
            try await sample.replace(attachment, withFileAt: source, allowedTypes: LessonAttachmentService.pdfOrImage)
        }

        #expect(try sample.rename(attachment, to: "Chart"))
        #expect(attachment.fileName == "Chart")
        #expect(attachment.fileRelativePath == "Geometry/Circle/circle.pdf", "the file stays as the notebook has it")

        try sample.remove(attachment)
        #expect(scratch.trash.given.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try scratch.lessonFolderNames() == ["circle.pdf"])
    }

    // MARK: - Finding by title

    @Test("Title matching uses the title as written in any case, and skips sequence, area and other lessons' files")
    func existingAttachmentByTitle() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let service = scratch.service()
        let allowed = LessonAttachmentService.pdfOrImage
        let own = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "a.pdf"), to: scratch.lesson,
            title: "Area of a Circle — remade", allowedTypes: allowed
        )
        #expect(own.fileRelativePath == "Geometry/Circle/Area of a Circle - remade.pdf")
        own.attachedAt = Self.earlier
        try scratch.context.save()
        // A second file whose title has a hyphen for the dash: on disk the two
        // names are alike (it gets a "-2"), but the titles are two.
        let second = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "a2.pdf"), to: scratch.lesson,
            title: "AREA of a Circle - remade", allowedTypes: allowed
        )
        #expect(second.fileRelativePath == "Geometry/Circle/AREA of a Circle - remade-2.pdf")
        #expect(service.existingAttachment(titled: "Area of a Circle — remade", on: scratch.lesson) == own)
        // The same title twice: the older file wins.
        let third = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "a3.pdf"), to: scratch.lesson,
            title: "area of a circle — REMADE", allowedTypes: allowed
        )
        #expect(third != own)
        #expect(service.existingAttachment(titled: "Area of a Circle — remade", on: scratch.lesson) == own)
        _ = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "b.pdf"), to: scratch.lesson, scope: .sequence,
            title: "Circle Chart", allowedTypes: allowed
        )
        _ = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "c.pdf"), to: scratch.lesson, scope: .area,
            title: "Geometry Chart", allowedTypes: allowed
        )
        let other = CoreDataTestHelpers.seedLesson(in: scratch.context, name: "Circumference", area: "Geometry")
        _ = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "d.pdf"), to: other, title: "Circumference Chart",
            allowedTypes: allowed
        )

        #expect(service.existingAttachment(titled: "area of a circle — REMADE", on: scratch.lesson) == own)
        #expect(service.existingAttachment(titled: "area of a circle - REMADE", on: scratch.lesson) == second)
        #expect(service.existingAttachment(titled: "Area of a Circle — remade.pdf", on: scratch.lesson) == own)
        #expect(service.existingAttachment(titled: "Area of a Circle", on: scratch.lesson) == nil)
        #expect(service.existingAttachment(titled: "Circle Chart", on: scratch.lesson) == nil, "sequence-wide")
        #expect(service.existingAttachment(titled: "Geometry Chart", on: scratch.lesson) == nil, "area-wide")
        #expect(service.existingAttachment(titled: "Circumference Chart", on: scratch.lesson) == nil)
        #expect(service.existingAttachment(titled: "  ", on: scratch.lesson) == nil)
    }
}
