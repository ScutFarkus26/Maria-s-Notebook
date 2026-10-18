import CoreData
import Foundation
import OSLog
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-17, files: a PDF dropped on Stories or Book Club (#20), a
/// stored file that arrives after its screen opened (#26), and renaming a
/// lesson attachment onto a name still in iCloud (#29).
@Suite("Files: dropped PDFs, late files and attachment names (bug hunt 10-17)")
@MainActor
struct FileHandlingFix1017AlTests {

    private static func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Fix1017Al-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: #20 Dropped PDFs

    @Test("A dropped PDF is imported under its own name, and its temp copy goes afterward")
    func droppedPDFKeepsItsName() throws {
        let source = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: source) }
        let dropped = source.appendingPathComponent("Bead Chains.pdf")
        try Data("pdf".utf8).write(to: dropped)

        let copy = try #require(PDFDropSupport.copyToTempIfNeeded(dropped, logger: .stories))
        #expect(copy.lastPathComponent == "Bead Chains.pdf")

        var importedName: String?
        let message = PDFDropSupport.importTempCopy(copy) { url in
            importedName = url.lastPathComponent
            #expect(FileManager.default.fileExists(atPath: url.path))
            return nil
        }

        #expect(message == nil)
        #expect(importedName == "Bead Chains.pdf")
        #expect(!FileManager.default.fileExists(atPath: copy.path))
        #expect(!FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: dropped.path))
    }

    @Test("A dropped PDF that can't be imported says why, and its temp copy still goes")
    func failedDropImportCleansUp() throws {
        let source = try Self.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: source) }
        let dropped = source.appendingPathComponent("Locked Story.pdf")
        try Data("pdf".utf8).write(to: dropped)
        let copy = try #require(PDFDropSupport.copyToTempIfNeeded(dropped, logger: .stories))

        let message = PDFDropSupport.importTempCopy(copy) { _ in "This PDF is locked with a password." }

        #expect(message == "This PDF is locked with a password.")
        #expect(!FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path))
    }

    // MARK: #26 A file that arrives later

    /// A stored file that comes down from iCloud while its screen is open.
    @MainActor
    private final class Download {
        static let report = URL(fileURLWithPath: "/Student Files/Ada/Report.pdf")
        var arrived = false

        func resolve(_ bookmark: Data?, _ path: String) -> URL? {
            arrived ? Self.report : nil
        }
    }

    @Test("A file that wasn't there when the screen opened is found once it arrives, then remembered")
    func memoFindsAFileThatArrives() async {
        let memo = DocumentFileURLMemo(recheckInterval: .milliseconds(20), recheckLimit: .seconds(10))
        let download = Download()

        // The screen opens before the file has come down from iCloud.
        #expect(memo.url(bookmark: Data([1]), relativePath: "Ada/Report", resolve: download.resolve) == nil)

        // The memo's next recheck (review a2 #10) finds it.
        download.arrived = true
        try? await Task.sleep(for: .milliseconds(100))
        #expect(memo.url(bookmark: Data([1]), relativePath: "Ada/Report", resolve: download.resolve)
            == Download.report)

        // Found once, the answer is kept for later redraws.
        for _ in 0..<10 {
            #expect(memo.url(bookmark: Data([1]), relativePath: "Ada/Report", resolve: download.resolve)
                == Download.report)
        }
        #expect(memo.resolutionCount == 2)
    }

    // MARK: #29 Renaming an attachment

    @Test("Renaming a lesson attachment skips a name another device's file still holds in iCloud")
    func renameSkipsANameStillInICloud() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CDLesson(context: context)
        lesson.name = "Bead Chains"
        lesson.area = "Fix1017 \(UUID().uuidString)"
        lesson.sequence = "Chains"
        let folder = try LessonFileStorage.organizationalDirectory(forLesson: lesson)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let file = folder.appendingPathComponent("Notes.pdf")
        try Data("notes".utf8).write(to: file)
        let attachment = CDLessonAttachment(context: context)
        attachment.lesson = lesson
        attachment.scope = .lesson
        attachment.fileRelativePath = try LessonFileStorage.relativePath(forManagedURL: file)
        // Another device's "Chart.pdf" hasn't downloaded here yet.
        let theirs = UbiquitousFile.placeholderURL(for: folder.appendingPathComponent("Chart.pdf"))
        try Data("stub".utf8).write(to: theirs)

        let renamed = try LessonFileStorage.renameAttachment(attachment, to: "Chart")

        #expect(renamed.url.lastPathComponent == "Chart-2.pdf")
        #expect(renamed.fileName == "Chart.pdf")
        #expect(FileManager.default.fileExists(atPath: theirs.path))
        #expect(try Data(contentsOf: renamed.url) == Data("notes".utf8))
    }
}
