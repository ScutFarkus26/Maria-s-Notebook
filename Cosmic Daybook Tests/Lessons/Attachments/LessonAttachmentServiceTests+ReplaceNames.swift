import CoreGraphics
import Foundation
import Testing
@testable import CosmicDaybook

/// The names a replace writes under (review of 2026-10-25, finding 2): each
/// copy is written once under a name the attachment never had, so names
/// never flip back to one an earlier replace sent to the Trash, which iCloud
/// has just deleted (`UbiquitousFile`: written once under a new name).
extension LessonAttachmentServiceTests {

    @Test("Three replaces in a row write under three new names, never one used before")
    func replacesNeverReuseAName() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let allowed = LessonAttachmentService.pdfOrImage
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson,
            title: "Area of a Circle", allowedTypes: allowed
        )
        var paths = [attachment.fileRelativePath]

        for (step, shade) in [0.1, 0.2, 0.3].enumerated() {
            let source = try scratch.write(Self.pdf(shade: shade), named: "circle-v\(step + 2).pdf")
            let outcome = try await scratch.service().replace(attachment, withFileAt: source, allowedTypes: allowed)

            #expect(outcome == .replaced)
            #expect(!paths.contains(attachment.fileRelativePath), "replace \(step + 1) went back to an old name")
            #expect(try Data(contentsOf: scratch.file(of: attachment)) == Data(contentsOf: source))
            paths.append(attachment.fileRelativePath)
        }

        #expect(paths == [
            "Geometry/Circle/Area of a Circle.pdf",
            "Geometry/Circle/Area of a Circle-2.pdf",
            "Geometry/Circle/Area of a Circle-3.pdf",
            "Geometry/Circle/Area of a Circle-4.pdf"
        ])
        #expect(scratch.trash.given.count == 3, "each old file went to the Trash after its replace")
        #expect(try scratch.lessonFolderNames() == ["Area of a Circle-4.pdf"])
    }

    @Test("A PDF replaced by a PNG and then by a PDF again never goes back to its first name")
    func replacesAcrossKindsNeverReuseAName() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let allowed = LessonAttachmentService.pdfOrImage
        let attachment = try scratch.service().add(
            fileAt: try scratch.write(Self.pdf(), named: "chart.pdf"), to: scratch.lesson,
            title: "Bead Chart", allowedTypes: allowed
        )

        _ = try await scratch.service().replace(
            attachment, withFileAt: try scratch.write(Self.png(), named: "chart.png"), allowedTypes: allowed
        )
        #expect(attachment.fileRelativePath == "Geometry/Circle/Bead Chart-2.png")
        _ = try await scratch.service().replace(
            attachment, withFileAt: try scratch.write(Self.pdf(shade: 0.8), named: "chart-v3.pdf"),
            allowedTypes: allowed
        )

        #expect(attachment.fileRelativePath == "Geometry/Circle/Bead Chart-3.pdf")
        #expect(attachment.fileName == "Bead Chart.pdf")
        #expect(try scratch.lessonFolderNames() == ["Bead Chart-3.pdf"])
    }

    @Test("A replace after a rename counts on from the new name")
    func replaceAfterRenameCountsFromTheNewName() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let allowed = LessonAttachmentService.pdfOrImage
        let service = scratch.service()
        let attachment = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson, allowedTypes: allowed
        )
        _ = try await service.replace(
            attachment, withFileAt: try scratch.write(Self.pdf(shade: 0.1), named: "v2.pdf"), allowedTypes: allowed
        )
        #expect(attachment.fileRelativePath == "Geometry/Circle/circle-2.pdf")

        #expect(try service.rename(attachment, to: "Chart"))
        #expect(attachment.fileRelativePath == "Geometry/Circle/Chart.pdf")
        _ = try await service.replace(
            attachment, withFileAt: try scratch.write(Self.pdf(shade: 0.2), named: "v3.pdf"), allowedTypes: allowed
        )

        #expect(attachment.fileRelativePath == "Geometry/Circle/Chart-2.pdf")
    }
}
