import CoreData
import Foundation
@preconcurrency import PDFKit
import Testing
@testable import CosmicDaybook

/// Simplify the app, Phase 6: stories, packets and resource files saved
/// before the Resources screen joined them still open. Files are found by
/// folder name, so a story saved in `Story Files/` and a packet saved in
/// `Book Club Files/` by the old storages must resolve through the new one.
@Suite("Resources: files saved under the old folder names still open (simplify phase 6)")
@MainActor
struct LibraryOldFoldersTests {

    @Test("The library folders keep the names the old storages used")
    func folderNames() {
        #expect(LibraryFileStorage.stories.folderName == "Story Files")
        #expect(LibraryFileStorage.packets.folderName == "Book Club Files")
        #expect(LibraryFileStorage.resources.folderName == "Resource Files")
    }

    @Test("A story and a packet written by the old storages open, by bookmark and by relative path alone")
    func oldStoryAndPacketOpen() async throws {
        let fm = FileManager.default
        let container = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: container) }
        // The layout the old StoryFileStorage and BookClubFileStorage wrote:
        // <container>/Documents/<folder>/<title>.pdf
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        let storyFolder = documents.appendingPathComponent("Story Files", isDirectory: true)
        let packetFolder = documents.appendingPathComponent("Book Club Files", isDirectory: true)
        try fm.createDirectory(at: storyFolder, withIntermediateDirectories: true)
        try fm.createDirectory(at: packetFolder, withIntermediateDirectories: true)
        let storyFile = storyFolder.appendingPathComponent("The Little Red Hen.pdf")
        let packetFile = packetFolder.appendingPathComponent("BookClub.pdf")
        try StudentFileThumbnailTests.makePDF().write(to: storyFile)
        try StudentFileThumbnailTests.makePDF().write(to: packetFile)

        let cache = UbiquityContainerCache(system: .init(identity: { 1 }, containerURL: { container }))
        var stories = LibraryFileStorage.stories
        stories.ubiquityContainer = cache
        var packets = LibraryFileStorage.packets
        packets.ubiquityContainer = cache

        let context = try CoreDataTestHelpers.makeContext()
        // Saved on another device: no bookmark that resolves here, only the path.
        let story = CDStory(context: context)
        story.pdfFileRelativePath = "The Little Red Hen.pdf"
        story.pdfFileBookmark = Data("a bookmark from another device".utf8)
        let packet = CDBookClubPacket(context: context)
        packet.packetPDFRelativePath = "BookClub.pdf"
        // Saved on this device: a bookmark to the file where it lies.
        let bookmarkedStory = CDStory(context: context)
        bookmarkedStory.pdfFileBookmark = try stories.makeBookmark(for: storyFile)
        bookmarkedStory.pdfFileRelativePath = ""

        let openedStory = try #require(LibraryFileStorage.url(for: story, in: stories))
        let openedPacket = try #require(LibraryFileStorage.url(for: packet, in: packets))
        let openedBookmarked = try #require(LibraryFileStorage.url(for: bookmarkedStory, in: stories))

        #expect(openedStory.standardizedFileURL == storyFile.standardizedFileURL)
        #expect(openedPacket.standardizedFileURL == packetFile.standardizedFileURL)
        #expect(openedBookmarked.standardizedFileURL == storyFile.standardizedFileURL)
        #expect(PDFDocument(url: openedStory)?.pageCount == 1)
        #expect(PDFDocument(url: openedPacket)?.pageCount == 1)

        // And the analysis path, which waits for the file to be on the device.
        let ready = await stories.readyURL(bookmark: story.pdfFileBookmark, relativePath: story.pdfFileRelativePath)
        #expect(ready?.standardizedFileURL == storyFile.standardizedFileURL)
    }

    @Test("A resource file saved under its category folder resolves through the new storage")
    func oldResourceFileResolves() throws {
        let fm = FileManager.default
        let container = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: container) }
        let folder = container
            .appendingPathComponent("Documents/Resource Files/Writing Papers", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("Cursive Lines.pdf")
        try StudentFileThumbnailTests.makePDF().write(to: file)

        var resources = LibraryFileStorage.resources
        resources.ubiquityContainer = UbiquityContainerCache(
            system: .init(identity: { 1 }, containerURL: { container })
        )

        let resolved = try resources.resolve(relativePath: "Writing Papers/Cursive Lines.pdf")
        #expect(resolved.standardizedFileURL == file.standardizedFileURL)
        #expect(resources.resolveURL(bookmark: nil, relativePath: "Writing Papers/Cursive Lines.pdf") != nil)
    }
}
