import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `attach_file_to_lesson`, `list_lesson_attachments` and
/// `remove_lesson_attachment` (plan "Lesson file attachments", Phase 2): each
/// parameter is shown to persist by reading the store back through a context
/// of its own, and through `list_lesson_attachments`, never from the receipt.
@Suite("MCP Lesson Attachment Tools")
@MainActor
struct MCPLessonAttachmentToolsTests {

    // MARK: - lesson

    @Test("lesson by id attaches to that lesson")
    func lessonByID() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let source = try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf")

        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(source.path))

        let stored = try #require(try fixture.stored().first)
        #expect(try fixture.stored().count == 1)
        #expect(stored.lessonID == fixture.lesson.id)
        #expect(stored.scope == .lesson)
    }

    @Test("lesson by exact name attaches to that lesson, beside one whose name contains it")
    func lessonByExactName() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let other = CoreDataTestHelpers.seedLesson(
            in: fixture.context, name: "Area of a Circle Review", area: "Geometry", sequence: "Circle"
        )
        other.id = UUID()
        try fixture.context.save()
        let source = try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf")

        _ = try await fixture.call("attach_file_to_lesson", [
            "lesson": "Area of a Circle", "path": .string(source.path)
        ])

        #expect(try fixture.stored().map(\.lessonID) == [fixture.lesson.id])
    }

    @Test("A lesson name that matches more than one lesson is refused, and nothing is written")
    func ambiguousLessonRefused() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let other = CoreDataTestHelpers.seedLesson(
            in: fixture.context, name: "Area of a Circle Review", area: "Geometry", sequence: "Circle"
        )
        other.id = UUID()
        try fixture.context.save()
        let source = try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf")

        let message = try await fixture.refusal("attach_file_to_lesson", [
            "lesson": "Area of", "path": .string(source.path)
        ])

        #expect(message.contains("More than one lesson matches"))
        try fixture.expectNothingWritten()
    }

    // MARK: - path, title, source_note

    @Test("path: the file's bytes are copied into the lesson's folder, and the original stays")
    func pathBytesCopied() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let bytes = LessonFileToolFixture.pdf()
        let source = try fixture.write(bytes, named: "Geometry/circle-area-of-a-circle.pdf")

        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(source.path))

        let stored = try #require(try fixture.stored().first)
        #expect(try fixture.bytes(of: stored) == bytes)
        #expect(stored.size == Int64(bytes.count))
        #expect(stored.fileType == "pdf")
        #expect(try fixture.lessonFolderNames().count == 1)
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("title is stored as given, em dash and all; without one the title is the file's own stem")
    func titleStoredAndDefaulted() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let first = try fixture.write(LessonFileToolFixture.pdf(0.2), named: "circle-area-of-a-circle.pdf")
        let second = try fixture.write(LessonFileToolFixture.pdf(0.4), named: "circle-diameter.pdf")

        _ = try await fixture.call(
            "attach_file_to_lesson", fixture.attach(first.path, title: "Area of a Circle — remade album pages")
        )
        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(second.path))

        let titles = try fixture.stored().map(\.title)
        #expect(titles == ["Area of a Circle — remade album pages", "circle-diameter"])
        #expect(try fixture.stored().first?.fileName == "Area of a Circle — remade album pages.pdf")
        let listing = try await fixture.call("list_lesson_attachments", ["lesson": "Area of a Circle"])
        #expect(listing.contains("'Area of a Circle — remade album pages'"))
        #expect(listing.contains("'circle-diameter'"))
    }

    @Test("source_note lands in the attachment's notes")
    func sourceNoteStored() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let source = try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf")

        _ = try await fixture.call(
            "attach_file_to_lesson", fixture.attach(source.path, note: "Remade Geometry album, October 2026")
        )

        #expect(try fixture.stored().first?.notes == "Remade Geometry album, October 2026")
        let listing = try await fixture.call("list_lesson_attachments", ["lesson": "Area of a Circle"])
        #expect(listing.contains("source: Remade Geometry album, October 2026"))
    }

    @Test("The receipt's title and size are the stored record's")
    func receiptMatchesStoredRecord() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let source = try fixture.write(LessonFileToolFixture.pdf(), named: "circle-area-of-a-circle.pdf")

        let receipt = try await fixture.call(
            "attach_file_to_lesson", fixture.attach(source.path, title: "Area of a Circle — remade album pages")
        )

        let stored = try #require(try fixture.stored().first)
        let id = try #require(stored.id)
        let lessonID = try #require(fixture.lesson.id)
        #expect(receipt == "Attached '\(stored.title)' (PDF, \(stored.sizeFormatted)) to [lesson id=\(lessonID)] "
            + "Area of a Circle — Geometry › Circle [lessonAttachment id=\(id)].")
        #expect(receipt.contains("'Area of a Circle — remade album pages'"))
    }

    // MARK: - replace_existing

    @Test("replace_existing: true keeps the same attachment and gives it the new contents")
    func replaceExistingTrue() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let oldBytes = LessonAttachmentServiceTests.pdf()
        let newBytes = LessonAttachmentServiceTests.pdf(size: CGSize(width: 1224, height: 1584), shade: 0.2)
        try #require(oldBytes.count != newBytes.count)
        let source = try fixture.write(oldBytes, named: "circle.pdf")
        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(source.path, title: "Area of a Circle"))
        let earlier = Date(timeIntervalSince1970: 1_790_000_000)
        let record = try #require(fixture.lesson.attachments?.allObjects.first as? CDLessonAttachment)
        record.modifiedAt = earlier
        try fixture.context.save()
        let before = try #require(try fixture.stored().first)

        try fixture.write(newBytes, named: "circle.pdf")
        let receipt = try await fixture.call(
            "attach_file_to_lesson", fixture.attach(source.path, title: "area of a circle", replace: true)
        )

        let after = try fixture.stored()
        #expect(after.count == 1)
        let stored = try #require(after.first)
        #expect(stored.id == before.id)
        #expect(stored.size == Int64(newBytes.count))
        #expect(stored.size != before.size)
        #expect(try fixture.bytes(of: stored) == newBytes)
        #expect((stored.modifiedAt ?? earlier) > earlier)
        #expect(stored.title == "Area of a Circle", "a replace keeps the stored title")
        #expect(receipt.hasPrefix("Replaced 'Area of a Circle' (PDF, \(stored.sizeFormatted)) on [lesson id="))
        let listing = try await fixture.call("list_lesson_attachments", ["lesson": "Area of a Circle"])
        #expect(listing.contains("1 file(s)"))
        #expect(listing.contains(stored.sizeFormatted))
    }

    @Test("Without replace_existing, or with it false, a same-title file is refused and nothing changes")
    func replaceExistingFalseRefused() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let oldBytes = LessonFileToolFixture.pdf(0.1)
        let source = try fixture.write(oldBytes, named: "circle.pdf")
        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(source.path, title: "Area of a Circle"))
        let before = try fixture.stored()
        let first = try #require(before.first)
        let folderBefore = try fixture.lessonFolderNames()
        try fixture.write(LessonFileToolFixture.pdf(0.9), named: "circle.pdf")

        for replace in [nil, false] as [Bool?] {
            let message = try await fixture.refusal(
                "attach_file_to_lesson", fixture.attach(source.path, title: "Area of a Circle", replace: replace)
            )
            #expect(message.contains("already has a file titled 'Area of a Circle' [lessonAttachment id="))
            #expect(message.contains("replace_existing: true"))
            #expect(try fixture.stored() == before)
            #expect(try fixture.lessonFolderNames() == folderBefore)
            #expect(try fixture.bytes(of: first) == oldBytes)
            #expect(!fixture.context.hasChanges)
        }
    }

    @Test("Replacing with identical bytes changes nothing and says so")
    func replaceWithIdenticalBytes() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let source = try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf")
        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(source.path))
        let before = try fixture.stored()

        let receipt = try await fixture.call("attach_file_to_lesson", fixture.attach(source.path, replace: true))

        #expect(receipt.hasPrefix("Already up to date: 'circle' (PDF, "))
        #expect(receipt.contains("Nothing changed."))
        #expect(try fixture.stored() == before)
        #expect(try fixture.lessonFolderNames().count == 1)
        #expect(fixture.trash.urls.isEmpty)
    }

    // MARK: - list and remove

    @Test("list_lesson_attachments shows the lesson's own files and a sequence-wide one from another lesson")
    func listShowsScopes() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let sibling = CoreDataTestHelpers.seedLesson(
            in: fixture.context, name: "Circumference", area: "Geometry", sequence: "Circle"
        )
        sibling.id = UUID()
        try fixture.context.save()
        let shared = try fixture.write(LessonFileToolFixture.png(), named: "circle-parts.png")
        try LessonAttachmentService(context: fixture.context, storage: fixture.storage).add(
            fileAt: shared, to: sibling, scope: .sequence, allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let own = try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf")
        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(own.path))

        let listing = try await fixture.call("list_lesson_attachments", ["lesson": "Area of a Circle"])
        let lines = listing.split(separator: "\n").map(String.init)

        #expect(lines.count == 3)
        #expect(lines.first?.hasSuffix("Area of a Circle — Geometry › Circle: 2 file(s)") == true)
        #expect(lines[1].contains("'circle' · this lesson · PDF"))
        #expect(lines[2].contains("'circle-parts' · whole sequence (from [lesson id="))
        #expect(lines[2].contains("Circumference — Geometry › Circle) · PNG"))
    }

    @Test("remove_lesson_attachment with confirm removes exactly the one named")
    func removeExactlyOne() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let first = try fixture.write(LessonFileToolFixture.pdf(0.2), named: "first.pdf")
        let second = try fixture.write(LessonFileToolFixture.pdf(0.6), named: "second.pdf")
        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(first.path))
        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(second.path))
        let before = try fixture.stored()
        let gone = try #require(before.first { $0.title == "first" })
        let goneFile = try fixture.storage.resolve(relativePath: gone.path)

        let receipt = try await fixture.call("remove_lesson_attachment", [
            "attachment": .string(gone.id?.uuidString ?? ""), "confirm": true
        ])

        #expect(receipt.hasPrefix("Removed 'first' (PDF, "))
        #expect(try fixture.stored().map(\.title) == ["second"])
        #expect(fixture.trash.urls.map(\.standardizedFileURL) == [goneFile.standardizedFileURL])
        let listing = try await fixture.call("list_lesson_attachments", ["lesson": "Area of a Circle"])
        #expect(listing.contains("1 file(s)") && !listing.contains("'first'"))
    }

    @Test("remove_lesson_attachment without confirm only reports, and changes nothing")
    func removeWithoutConfirm() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let source = try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf")
        _ = try await fixture.call("attach_file_to_lesson", fixture.attach(source.path))
        let before = try fixture.stored()

        let report = try await fixture.call("remove_lesson_attachment", [
            "attachment": .string(before.first?.id?.uuidString ?? "")
        ])

        #expect(report.hasPrefix("remove_lesson_attachment refused — nothing has been changed."))
        #expect(report.contains("Removing 'circle' (PDF, "))
        #expect(try fixture.stored() == before)
        #expect(try fixture.lessonFolderNames().count == 1)
        #expect(fixture.trash.urls.isEmpty)
        #expect(!fixture.context.hasChanges)
    }
}
