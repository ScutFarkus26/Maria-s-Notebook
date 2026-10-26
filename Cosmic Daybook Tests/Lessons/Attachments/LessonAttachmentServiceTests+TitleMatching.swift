import Foundation
import Testing
@testable import CosmicDaybook

/// Matching a lesson file by its title (review of 2026-10-25, finding 1): the
/// title as the card shows it, in any case and with or without accents, never
/// the name on disk, which keeps ASCII only, so "Fractions ½" and
/// "Fractions ¼", or two Hebrew titles, used to read as one.
extension LessonAttachmentServiceTests {

    @Test("Titles that differ only in a fraction are two titles, though their names on disk are alike")
    func titlesDifferingInAFraction() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let service = scratch.service()
        let allowed = LessonAttachmentService.pdfOrImage
        let half = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "half.pdf"), to: scratch.lesson,
            title: "Fractions ½", allowedTypes: allowed
        )
        #expect(half.fileRelativePath == "Geometry/Circle/Fractions.pdf", "the name on disk drops the ½")

        #expect(service.existingAttachment(titled: "Fractions ½", on: scratch.lesson) == half)
        #expect(service.existingAttachment(titled: "Fractions ¼", on: scratch.lesson) == nil)
        #expect(service.existingAttachment(titled: "Fractions", on: scratch.lesson) == nil)

        let quarter = try service.add(
            fileAt: try scratch.write(Self.pdf(shade: 0.2), named: "quarter.pdf"), to: scratch.lesson,
            title: "Fractions ¼", allowedTypes: allowed
        )
        #expect(service.existingAttachment(titled: "Fractions ¼", on: scratch.lesson) == quarter)
        #expect(service.existingAttachment(titled: "Fractions ½", on: scratch.lesson) == half)
    }

    @Test("Two Hebrew titles are two titles")
    func hebrewTitles() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let service = scratch.service()
        let allowed = LessonAttachmentService.pdfOrImage
        let bereshit = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "bereshit.pdf"), to: scratch.lesson,
            title: "Parsha בראשית", allowedTypes: allowed
        )

        #expect(service.existingAttachment(titled: "Parsha נח", on: scratch.lesson) == nil)
        #expect(service.existingAttachment(titled: "Parsha", on: scratch.lesson) == nil)
        #expect(service.existingAttachment(titled: "Parsha בראשית", on: scratch.lesson) == bereshit)

        let noach = try service.add(
            fileAt: try scratch.write(Self.pdf(shade: 0.2), named: "noach.pdf"), to: scratch.lesson,
            title: "Parsha נח", allowedTypes: allowed
        )
        let allHebrew = try service.add(
            fileAt: try scratch.write(Self.pdf(shade: 0.3), named: "lech-lecha.pdf"), to: scratch.lesson,
            title: "לך לך", allowedTypes: allowed
        )
        #expect(service.existingAttachment(titled: "Parsha נח", on: scratch.lesson) == noach)
        #expect(service.existingAttachment(titled: "Parsha בראשית", on: scratch.lesson) == bereshit)
        #expect(service.existingAttachment(titled: "לך לך", on: scratch.lesson) == allHebrew)
        #expect(service.existingAttachment(titled: "וירא", on: scratch.lesson) == nil)
    }

    @Test("Case, accents, spaces round the title and its own extension still don't make another title")
    func caseAndAccentsStillMatch() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let service = scratch.service()
        let foo = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "a.pdf"), to: scratch.lesson,
            title: "Foo", allowedTypes: LessonAttachmentService.pdfOrImage
        )
        let cafe = try service.add(
            fileAt: try scratch.write(Self.pdf(shade: 0.2), named: "b.pdf"), to: scratch.lesson,
            title: "Café Fractions", allowedTypes: LessonAttachmentService.pdfOrImage
        )

        #expect(service.existingAttachment(titled: "foo", on: scratch.lesson) == foo)
        #expect(service.existingAttachment(titled: "FOO", on: scratch.lesson) == foo)
        #expect(service.existingAttachment(titled: "  Foo ", on: scratch.lesson) == foo)
        #expect(service.existingAttachment(titled: "Foo.pdf", on: scratch.lesson) == foo)
        #expect(service.existingAttachment(titled: " foo.PDF ", on: scratch.lesson) == foo)
        #expect(service.existingAttachment(titled: "cafe fractions", on: scratch.lesson) == cafe)
        #expect(service.existingAttachment(titled: "Foo 2", on: scratch.lesson) == nil)
    }
}
