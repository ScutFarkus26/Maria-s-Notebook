import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The last look at a source before it is copied (review of 2026-10-25,
/// finding 4): add and replace hand `confirmingSource` the exact file they
/// will copy from, its links followed, and copy nothing when it refuses.
extension LessonAttachmentServiceTests {

    struct SourceMoved: Error {}

    @Test("Add confirms the very file it copies from, links followed, and copies nothing when refused")
    func addConfirmsItsSource() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let allowed = LessonAttachmentService.pdfOrImage
        let service = scratch.service()
        let real = try scratch.write(Self.pdf(), named: "circle.pdf")
        let link = scratch.sources.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        var confirmed: [String] = []

        _ = try service.add(
            fileAt: link, to: scratch.lesson, allowedTypes: allowed,
            confirmingSource: { confirmed.append(PathContainment.realPath(of: $0)) }
        )
        #expect(confirmed == [PathContainment.realPath(of: real)])

        #expect(throws: SourceMoved.self) {
            try service.add(
                fileAt: real, to: scratch.lesson, title: "Second", allowedTypes: allowed,
                confirmingSource: { _ in throw SourceMoved() }
            )
        }
        #expect((scratch.lesson.attachments?.count ?? 0) == 1)
        #expect(try scratch.lessonFolderNames() == ["circle.pdf"], "copied from where the link leads")
        #expect(!scratch.context.hasChanges)
    }

    @Test("Replace confirms its source before it compares and before it copies, and changes nothing when refused")
    func replaceConfirmsItsSource() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let allowed = LessonAttachmentService.pdfOrImage
        let service = scratch.service()
        let attachment = try service.add(
            fileAt: try scratch.write(Self.pdf(), named: "circle.pdf"), to: scratch.lesson, allowedTypes: allowed
        )
        let path = attachment.fileRelativePath
        let source = try scratch.write(Self.pdf(shade: 0.1), named: "circle-v2.pdf")
        var looks = 0

        await #expect(throws: SourceMoved.self) {
            try await service.replace(
                attachment, withFileAt: source, allowedTypes: allowed,
                confirmingSource: { _ in
                    looks += 1
                    // The first look passes; by the copy the file is elsewhere.
                    if looks > 1 { throw SourceMoved() }
                }
            )
        }
        #expect(looks == 2)
        #expect(attachment.fileRelativePath == path)
        #expect(try scratch.lessonFolderNames() == ["circle.pdf"])
        #expect(scratch.trash.given.isEmpty)
        #expect(!scratch.context.hasChanges)

        var seen: [String] = []
        let outcome = try await service.replace(
            attachment, withFileAt: source, allowedTypes: allowed,
            confirmingSource: { seen.append(PathContainment.realPath(of: $0)) }
        )
        #expect(outcome == .replaced)
        #expect(seen == Array(repeating: PathContainment.realPath(of: source), count: 2))
    }
}
