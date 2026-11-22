import Foundation
import Testing
@testable import CosmicDaybook

/// Three screens draw a stored document's file once per stored value instead
/// of on every redraw: the Student Files card's thumbnail, the Book Club
/// packet's Open PDF button and the resource detail's Share and Print items.
/// Opening, deleting and printing still resolve afresh. These pin that the
/// memo answers what each library's resolver answers (the old expressions
/// kept verbatim below) and resolves again only when the bookmark or the
/// relative path changes, or while the file hasn't been found: one still
/// coming from iCloud is found once it lands (bug hunt 10-17 #26).
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

    @Test("A missing file is looked for again at the memo's rechecks, not on each redraw (review a2 #10)")
    func missingFileIsLookedForAgain() {
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
}
