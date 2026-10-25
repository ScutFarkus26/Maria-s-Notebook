import CoreData
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import CosmicDaybook

/// What `validate(fileAt:allowedTypes:)` refuses and accepts.
extension LessonAttachmentServiceTests {
    @Test("Validate refuses a Word file, a non-PDF named .pdf, a folder, a missing file and 50 MB + 1 byte")
    func validateRefusals() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let allowed = LessonAttachmentService.pdfOrImage
        typealias Problem = LessonAttachmentService.Problem

        let word = try scratch.write(Data("PK not really a document".utf8), named: "Notes.docx")
        #expect(throws: Problem.wrongType(allowed: "a PDF or an image")) {
            try LessonAttachmentService.validate(fileAt: word, allowedTypes: allowed)
        }
        let fakePDF = try scratch.write(Data("just some text".utf8), named: "Circle.pdf")
        #expect(throws: Problem.notReadable(kind: "a PDF")) {
            try LessonAttachmentService.validate(fileAt: fakePDF, allowedTypes: allowed)
        }
        let fakePNG = try scratch.write(Data("not pixels".utf8), named: "Chart.png")
        #expect(throws: Problem.notReadable(kind: "an image")) {
            try LessonAttachmentService.validate(fileAt: fakePNG, allowedTypes: allowed)
        }
        let folder = scratch.sources.appendingPathComponent("Album Pages", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(throws: Problem.folder) {
            try LessonAttachmentService.validate(fileAt: folder, allowedTypes: LessonAttachmentService.anyFile)
        }
        let missing = scratch.sources.appendingPathComponent("Gone.pdf")
        #expect(throws: Problem.fileMissing) {
            try LessonAttachmentService.validate(fileAt: missing, allowedTypes: allowed)
        }
        let header = Data("%PDF-1.7\n".utf8)
        let tooBig = try scratch.sparseFile(
            named: "Big.pdf", size: LessonAttachmentService.maximumFileSize + 1, header: header
        )
        #expect(throws: Problem.tooLarge) {
            try LessonAttachmentService.validate(fileAt: tooBig, allowedTypes: allowed)
        }
        // The card takes any kind of file, but not one over the limit either.
        #expect(throws: Problem.tooLarge) {
            try LessonAttachmentService.validate(fileAt: tooBig, allowedTypes: LessonAttachmentService.anyFile)
        }
        // A refused file is never copied in.
        #expect(throws: Problem.self) {
            try scratch.service().add(fileAt: word, to: scratch.lesson, allowedTypes: allowed)
        }
        #expect(try scratch.lessonFolderNames().isEmpty)
        #expect(!scratch.context.hasChanges)
    }

    @Test("Validate accepts a real PDF, a real image, exactly 50 MB, and any file for the card")
    func validateAcceptances() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let allowed = LessonAttachmentService.pdfOrImage

        let pdf = try scratch.write(Self.pdf(), named: "Circle.pdf")
        let checkedPDF = try LessonAttachmentService.validate(fileAt: pdf, allowedTypes: allowed)
        #expect(checkedPDF.contentType.conforms(to: .pdf))
        #expect(checkedPDF.size == Int64(Self.pdf().count))
        let png = try scratch.write(Self.png(), named: "Chart.png")
        let checkedPNG = try LessonAttachmentService.validate(fileAt: png, allowedTypes: allowed)
        #expect(checkedPNG.contentType.conforms(to: .image))
        let atLimit = try scratch.sparseFile(
            named: "Limit.pdf", size: LessonAttachmentService.maximumFileSize, header: Data("%PDF-1.7\n".utf8)
        )
        #expect(try LessonAttachmentService.validate(fileAt: atLimit, allowedTypes: allowed).size
            == LessonAttachmentService.maximumFileSize)
        // The Files card still takes a Word file, as it did.
        let word = try scratch.write(Data("PK".utf8), named: "Notes.docx")
        #expect(try LessonAttachmentService.validate(fileAt: word, allowedTypes: LessonAttachmentService.anyFile)
            .size == 2)
    }
}
