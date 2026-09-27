import Foundation
import Testing
@testable import CosmicDaybook

/// Three screens draw a stored document's file once per stored value instead
/// of on every redraw: the Student Files card's thumbnail, the Book Club
/// packet's Open PDF button and the resource detail's Share and Print items.
/// Opening, deleting and printing still resolve afresh. These pin that the
/// memo answers what each library's resolver answers (the old expressions
/// kept verbatim below), resolves again only when the bookmark or the
/// relative path changes, and remembers a missing file as missing rather
/// than asking again.
@Suite("Document file memo")
@MainActor
struct DocumentFileURLMemoTests {

    /// Stands in for the storage and records what it was asked.
    @MainActor
    private final class Storage {
        var asked: [String] = []
        var finds = true

        func resolve(_ bookmark: Data?, _ path: String) -> URL? {
            asked.append("\(bookmark?.count ?? -1)|\(path)")
            return finds ? URL(fileURLWithPath: "/Student Files/\(path).pdf") : nil
        }
    }

    @Test("Fifty redraws resolve once; a new bookmark or relative path resolves again")
    func resolvesOncePerValue() {
        let memo = DocumentFileURLMemo()
        let storage = Storage()
        let first = Data([1, 2, 3])
        let expected = URL(fileURLWithPath: "/Student Files/Ada/Report.pdf")

        for _ in 0..<50 {
            #expect(memo.url(bookmark: first, relativePath: "Ada/Report", resolve: storage.resolve) == expected)
        }
        #expect(storage.asked == ["3|Ada/Report"])
        #expect(memo.resolutionCount == 1)

        // A new bookmark, a new path, and no bookmark at all each resolve once.
        _ = memo.url(bookmark: Data([9]), relativePath: "Ada/Report", resolve: storage.resolve)
        _ = memo.url(bookmark: Data([9]), relativePath: "Ada/Other", resolve: storage.resolve)
        _ = memo.url(bookmark: nil, relativePath: "Ada/Other", resolve: storage.resolve)
        _ = memo.url(bookmark: nil, relativePath: "Ada/Other", resolve: storage.resolve)
        #expect(storage.asked == ["3|Ada/Report", "1|Ada/Report", "1|Ada/Other", "-1|Ada/Other"])

        // Only the latest value is kept: going back resolves again.
        _ = memo.url(bookmark: first, relativePath: "Ada/Report", resolve: storage.resolve)
        #expect(memo.resolutionCount == 5)
    }

    @Test("A missing file is remembered as missing, as the redraw that found it saw it")
    func missingFileStaysMissing() {
        let memo = DocumentFileURLMemo()
        let storage = Storage()
        storage.finds = false
        for _ in 0..<10 {
            #expect(memo.url(bookmark: Data([1]), relativePath: "Gone", resolve: storage.resolve) == nil)
        }
        #expect(storage.asked.count == 1)
    }

    @Test("With real files the memo answers exactly what the storage answers, present or gone")
    func answersWhatTheStorageAnswers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("Report.pdf")
        try StudentFileThumbnailTests.makePDF().write(to: file)
        let bookmark = try StudentDocumentFileStorage.storage.makeBookmark(for: file)

        let fresh = StudentDocumentFileStorage.resolveURL(bookmark: bookmark, relativePath: "")
        #expect(fresh?.resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path)
        let memo = DocumentFileURLMemo()
        let resolve = StudentDocumentFileStorage.resolveURL
        #expect(memo.url(bookmark: bookmark, relativePath: "", resolve: resolve) == fresh)
        #expect(memo.url(bookmark: bookmark, relativePath: "", resolve: resolve) == fresh)
        #expect(memo.resolutionCount == 1)

        // Once the file is gone the storage finds nothing — what a tap, which
        // resolves afresh, now sees — and a card drawn from then on is told
        // the same.
        try FileManager.default.removeItem(at: file)
        #expect(StudentDocumentFileStorage.resolveURL(bookmark: bookmark, relativePath: "") == nil)
        #expect(DocumentFileURLMemo().url(bookmark: bookmark, relativePath: "", resolve: resolve) == nil)
    }

    // MARK: - The Book Club packet's Open PDF button

    /// `BookClubPacketDetailView.resolvedURL()` before the change, verbatim
    /// but for the packet's two columns, which it read in place.
    private func oldPacketPDF(bookmark: Data?, relativePath: String) -> URL? {
        BookClubFileStorage.resolveURL(
            bookmark: bookmark,
            relativePath: relativePath
        )
    }

    /// A packet's two stored columns, and whether the PDF should be found.
    private struct PacketCase {
        let bookmark: Data?
        let path: String
        let found: Bool
    }

    @Test("The Open PDF check answers what the old one did: present, moved, gone with a fallback, gone")
    func packetPDFMatchesTheOldCheck() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        func bookmarkedPDF(_ name: String) throws -> (url: URL, bookmark: Data) {
            let url = scratch.appendingPathComponent(name)
            try StudentFileThumbnailTests.makePDF().write(to: url)
            return (url, try BookClubFileStorage.storage.makeBookmark(for: url))
        }

        let present = try bookmarkedPDF("Present.pdf")
        let moved = try bookmarkedPDF("Moved.pdf")
        try FileManager.default.moveItem(at: moved.url, to: scratch.appendingPathComponent("Renamed.pdf"))
        let gone = try bookmarkedPDF("Gone.pdf")
        try FileManager.default.removeItem(at: gone.url)
        // A file under the managed folder that only the relative path names.
        let fallbackName = "Fallback \(UUID().uuidString).pdf"
        let fallback = try BookClubFileStorage.packetFilesDirectory().appendingPathComponent(fallbackName)
        try StudentFileThumbnailTests.makePDF().write(to: fallback)
        defer { try? FileManager.default.removeItem(at: fallback) }

        let cases = [
            PacketCase(bookmark: present.bookmark, path: "", found: true),
            PacketCase(bookmark: moved.bookmark, path: "Moved.pdf", found: true),
            PacketCase(bookmark: gone.bookmark, path: fallbackName, found: true),
            PacketCase(bookmark: gone.bookmark, path: "Nowhere.pdf", found: false),
            PacketCase(bookmark: nil, path: fallbackName, found: true),
            PacketCase(bookmark: nil, path: "", found: false)
        ]
        for item in cases {
            let old = oldPacketPDF(bookmark: item.bookmark, relativePath: item.path)
            #expect((old != nil) == item.found)
            let memo = DocumentFileURLMemo()
            for _ in 0..<20 {
                let drawn = memo.url(
                    bookmark: item.bookmark, relativePath: item.path, resolve: BookClubFileStorage.resolveURL
                )
                #expect(drawn == old)
            }
            #expect(memo.resolutionCount == 1)
        }
        // The moved file is found where it went, as the bookmark always found it.
        let movedTo = oldPacketPDF(bookmark: moved.bookmark, relativePath: "Moved.pdf")
        #expect(movedTo?.lastPathComponent == "Renamed.pdf")
    }

    // MARK: - The resource detail's Share and Print items

    /// `ResourceDetailView.resolvedFileURL` before the change, verbatim but
    /// for the resource's column, which it read in place.
    private func oldResourceFile(relativePath: String) -> URL? {
        guard !relativePath.isEmpty else { return nil }
        return try? ResourceFileStorage.resolve(relativePath: relativePath)
    }

    @Test("The Share and Print check answers what the old one did, a missing file included")
    func resourceFileMatchesTheOldCheck() throws {
        let name = "Other/Chart \(UUID().uuidString).pdf"
        let file = try ResourceFileStorage.resolve(relativePath: name)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try StudentFileThumbnailTests.makePDF().write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        // A missing file still gets its URL, so Share and Print stay offered
        // for it as they always were; an empty path gets none.
        for path in [name, "Other/Missing \(UUID().uuidString).pdf", ""] {
            let old = oldResourceFile(relativePath: path)
            #expect(ResourceFileStorage.fileURL(relativePath: path) == old)
            #expect((old == nil) == path.isEmpty)
            let memo = DocumentFileURLMemo()
            for _ in 0..<20 {
                #expect(memo.url(relativePath: path, resolve: ResourceFileStorage.fileURL) == old)
            }
            #expect(memo.resolutionCount == 1)
        }
    }
}
