import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A file more than one record uses (review of 2026-10-25, finding 6): a
/// synced copy of the record, or the Sample Class's copy of the lesson while
/// it's open. Renaming one record copies the file to its new name rather
/// than taking it from the others, and no change in the real notebook sends
/// a file the open Sample Class shows to the Trash.
extension LessonAttachmentServiceTests {

    /// A second record on `attachment`'s file, on another lesson.
    private func sharer(of attachment: CDLessonAttachment, in scratch: Scratch) throws -> CDLessonAttachment {
        let sharer = CDLessonAttachment(context: scratch.context)
        sharer.fileName = attachment.fileName
        sharer.fileRelativePath = attachment.fileRelativePath
        sharer.fileType = attachment.fileType
        sharer.lesson = CoreDataTestHelpers.seedLesson(in: scratch.context, name: "Circumference")
        try scratch.context.save()
        return sharer
    }

    @Test("Renaming one of two records on one file copies it to the new name and leaves the other's in place")
    func renameASharedFile() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let service = scratch.service()
        let bytes = Self.pdf()
        let attachment = try service.add(
            fileAt: try scratch.write(bytes, named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let other = try sharer(of: attachment, in: scratch)
        let sharedURL = try scratch.file(of: other)

        #expect(try service.rename(attachment, to: "Chart"))

        #expect(attachment.fileName == "Chart.pdf")
        #expect(attachment.fileRelativePath == "Geometry/Circle/Chart.pdf")
        #expect(try Data(contentsOf: scratch.file(of: attachment)) == bytes)
        #expect(other.fileRelativePath == "Geometry/Circle/circle.pdf")
        #expect(try Data(contentsOf: sharedURL) == bytes, "the other record's file stays where it was")
        #expect(try scratch.lessonFolderNames() == ["Chart.pdf", "circle.pdf"])
        #expect(scratch.trash.given.isEmpty)
        #expect(!scratch.context.hasChanges)
    }

    @Test("A rename of a shared file whose save fails removes the copy and keeps the original")
    func renameASharedFileWhoseSaveFails() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        _ = try sharer(of: attachment, in: scratch)

        #expect(throws: LessonAttachmentService.Problem.saveFailed) {
            try scratch.service(save: { _ in throw SaveRefused() }).rename(attachment, to: "Chart")
        }

        #expect(attachment.fileName == "circle.pdf")
        #expect(attachment.fileRelativePath == "Geometry/Circle/circle.pdf")
        #expect(try scratch.lessonFolderNames() == ["circle.pdf"])
    }

    @Test("A file the open Sample Class shows is never moved or trashed by a change in the real notebook")
    func sampleClassFilesStay() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let allowed = LessonAttachmentService.pdfOrImage
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson, allowedTypes: allowed
        )
        // The Sample Class, opened: its lessons are copies on the real files.
        let sample = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        func openSampleClass() throws {
            let lessons = try SampleClassroomSeeder.lessonSnapshots(from: scratch.context)
            try SampleClassroomSeeder.mirror(lessons: lessons, into: sample)
        }
        try openSampleClass()
        let service = scratch.service(otherNotebooks: { [sample] })
        let circle = try scratch.file(of: attachment)

        // A rename copies: the Sample Class still shows circle.pdf.
        #expect(try service.rename(attachment, to: "Chart"))
        #expect(FileManager.default.fileExists(atPath: circle.path))
        #expect(try scratch.lessonFolderNames() == ["Chart.pdf", "circle.pdf"])

        // Opened again, it shows Chart.pdf; a replace keeps that for it.
        try openSampleClass()
        let chart = try scratch.file(of: attachment)
        _ = try await service.replace(
            attachment, withFileAt: try scratch.write(Self.pdf(shade: 0.1), named: "v2.pdf"), allowedTypes: allowed
        )
        #expect(scratch.trash.given.isEmpty, "the Sample Class shows the old file")
        #expect(FileManager.default.fileExists(atPath: chart.path))

        // A file only the real notebook uses still goes to the Trash.
        let replaced = try scratch.file(of: attachment)
        try service.remove(attachment)
        #expect(scratch.trash.given.map(\.standardizedFileURL) == [replaced.standardizedFileURL])
    }

    @Test("While the Sample Class is showing, the Files card's service keeps its files without being told")
    func sampleClassIsFoundWhileShowing() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let sample = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let lessons = try SampleClassroomSeeder.lessonSnapshots(from: scratch.context)
        try SampleClassroomSeeder.mirror(lessons: lessons, into: sample)
        let circle = try scratch.file(of: attachment)
        let trash = scratch.trash
        // The default the Files card and the MCP tools use. Nothing here
        // suspends, so no other test sees the Sample Class set.
        LessonFileStorage.showingSampleClass = sample
        defer { LessonFileStorage.showingSampleClass = nil }
        let service = LessonAttachmentService(
            context: scratch.context, storage: scratch.storage, trash: { trash.move($0) }
        )

        #expect(try service.rename(attachment, to: "Chart"))

        #expect(FileManager.default.fileExists(atPath: circle.path))
    }
}
