import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A file that changes between the folder check and the read (review of
/// 2026-10-25, finding 4): the file is checked again where it really is, just
/// before it is copied, and refused when it now leads out of the folders.
extension MCPLessonAttachmentPathTests {

    @Test("A file swapped for a link pointing out of the folder after the check is refused, and nothing is copied")
    func swapAfterTheCheckRefused() async throws {
        let fixture = try LessonFileToolFixture()
        defer { fixture.remove() }
        let secret = try fixture.write(LessonFileToolFixture.pdf(0.9), named: "secret.pdf", in: fixture.outside)
        let target = try fixture.write(LessonFileToolFixture.pdf(), named: "circle.pdf")
        var files = fixture.files
        // Stands in for another process swapping the file once the path passed.
        files.folders.afterCheck = { checked in
            try? FileManager.default.removeItem(at: checked)
            try? FileManager.default.createSymbolicLink(at: checked, withDestinationURL: secret)
        }
        let context = fixture.context
        let tools = MCPNotebookTools.makeTools(context: { context }, lessonFiles: files)
        let attach = try #require(tools.first { $0.name == "attach_file_to_lesson" })

        let refusal = await #expect(throws: MCPToolError.self) {
            _ = try await attach.handler(fixture.attach(target.path))
        }
        #expect(refusal?.message.contains("isn't in a folder the guide has let Claude attach files from") == true)

        try fixture.expectNothingWritten()
        let link = try FileManager.default.destinationOfSymbolicLink(atPath: target.path)
        #expect(PathContainment.realPath(of: URL(fileURLWithPath: link)) == PathContainment.realPath(of: secret),
                "the swap happened")
    }
}
