import CoreData
import Foundation
@preconcurrency import PDFKit
import Testing
@testable import CosmicDaybook

/// Simplify the app, Phase 6: one import service for the Resources screen.
/// A PDF still comes in as a story and as a book club packet, each into its
/// own folder under the name it always had; a file still comes in as a
/// resource under its category.
@Suite("Resources: one import service (simplify phase 6)")
@MainActor
struct LibraryImportServiceTests {

    /// A scratch iCloud container, the library folders pointed into it, and a
    /// PDF to import from outside it.
    private struct Scratch {
        let root: URL
        let stories: ManagedPDFFileStorage
        let packets: ManagedPDFFileStorage
        let resources: ManagedPDFFileStorage

        init() throws {
            root = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            let container = root.appendingPathComponent("Container", isDirectory: true)
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            let cache = UbiquityContainerCache(system: .init(identity: { 1 }, containerURL: { container }))
            var stories = LibraryFileStorage.stories
            stories.ubiquityContainer = cache
            var packets = LibraryFileStorage.packets
            packets.ubiquityContainer = cache
            var resources = LibraryFileStorage.resources
            resources.ubiquityContainer = cache
            self.stories = stories
            self.packets = packets
            self.resources = resources
        }

        /// A one-page PDF named `name`, outside the library folders.
        func sourcePDF(named name: String) throws -> URL {
            let folder = root.appendingPathComponent("Source", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try StudentFileThumbnailTests.makePDF().write(to: url)
            return url
        }

        func remove() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    @Test("A PDF imports as a story into Story Files, titled after the file, with its page count and thumbnail")
    func importsAStory() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let context = try CoreDataTestHelpers.makeContext()
        let source = try scratch.sourcePDF(named: "Pond_Life-Unit.pdf")

        let story = try LibraryImportService.importStory(at: source, context: context, storage: scratch.stories)

        #expect(story.title == "Pond Life Unit")
        #expect(story.pdfFileRelativePath == "Pond Life Unit.pdf")
        #expect(story.pageCount == 1)
        #expect(story.thumbnailData != nil)
        #expect(!story.hasChanges, "the import saves the new story")
        let copied = try scratch.stories.directory().appendingPathComponent("Pond Life Unit.pdf")
        #expect(copied.deletingLastPathComponent().lastPathComponent == "Story Files")
        #expect(FileManager.default.fileExists(atPath: copied.path))
        #expect(LibraryFileStorage.url(for: story, in: scratch.stories) == copied)
    }

    @Test("A PDF imports as a packet into Book Club Files, titled after the file, with its page count and thumbnail")
    func importsAPacket() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let context = try CoreDataTestHelpers.makeContext()
        let source = try scratch.sourcePDF(named: "Charlotte's Web.pdf")

        let packet = try LibraryImportService.importPacket(at: source, context: context, storage: scratch.packets)

        #expect(packet.title == "Charlotte's Web")
        #expect(packet.packetPDFRelativePath == "Charlotte-s Web.pdf", "the old filename scheme")
        #expect(packet.pageCount == 1)
        #expect(packet.thumbnailData != nil)
        #expect(!packet.hasChanges, "the import saves the new packet")
        let copied = try #require(LibraryFileStorage.url(for: packet, in: scratch.packets))
        #expect(copied.deletingLastPathComponent().lastPathComponent == "Book Club Files")
        #expect(PDFDocument(url: copied)?.pageCount == 1)
    }

    @Test("The same title twice gets a numbered file, as before")
    func secondImportIsNumbered() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let context = try CoreDataTestHelpers.makeContext()
        let source = try scratch.sourcePDF(named: "Owl Moon.pdf")

        let first = try LibraryImportService.importStory(at: source, context: context, storage: scratch.stories)
        let second = try LibraryImportService.importStory(at: source, context: context, storage: scratch.stories)

        #expect(first.pdfFileRelativePath == "Owl Moon.pdf")
        #expect(second.pdfFileRelativePath == "Owl Moon-2.pdf")
    }

    @Test("A file that isn't a PDF is turned down in each library's own words, and nothing is saved")
    func rejectsNonPDFs() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let context = try CoreDataTestHelpers.makeContext()
        let text = scratch.root.appendingPathComponent("Notes.txt")
        try Data("hello".utf8).write(to: text)

        #expect(throws: LibraryImportService.ImportRejection.notAPDF(.story)) {
            try LibraryImportService.importStory(at: text, context: context, storage: scratch.stories)
        }
        #expect(throws: LibraryImportService.ImportRejection.notAPDF(.packet)) {
            try LibraryImportService.importPacket(at: text, context: context, storage: scratch.packets)
        }
        #expect(LibraryImportService.ImportRejection.notAPDF(.story).errorDescription
                == "Only PDF files can be added as stories.")
        #expect(LibraryImportService.ImportRejection.notAPDF(.packet).errorDescription
                == "Only PDF files can be added as book club packets.")
        #expect(context.registeredObjects.isEmpty)
    }

    @Test("A PDF that has gone is turned down plainly")
    func rejectsAMissingFile() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let context = try CoreDataTestHelpers.makeContext()
        let missing = scratch.root.appendingPathComponent("Gone.pdf")

        do {
            try LibraryImportService.importPacket(at: missing, context: context, storage: scratch.packets)
            Issue.record("A missing file imported")
        } catch {
            #expect(LibraryImportService.message(for: error)
                    == "Couldn't find that PDF. It may have been moved or deleted.")
        }
    }

    @Test("A resource file keeps its extension and lands in its category's folder")
    func importsAResourceFile() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let source = scratch.root.appendingPathComponent("Cursive Lines.docx")
        try Data("not a pdf".utf8).write(to: source)

        let file = try LibraryImportService.importResourceFile(
            from: source, title: "Cursive Lines", category: .writingPapers, storage: scratch.resources
        )

        #expect(file.relativePath == "Writing Papers/Cursive Lines.docx")
        #expect(file.fileSizeBytes == 9)
        #expect(file.thumbnail == nil, "only a PDF has a first page to draw")
        let stored = try scratch.resources.resolve(relativePath: file.relativePath)
        #expect(stored.pathComponents.suffix(3) == ["Resource Files", "Writing Papers", "Cursive Lines.docx"])
        #expect(FileManager.default.fileExists(atPath: stored.path))
    }
}
