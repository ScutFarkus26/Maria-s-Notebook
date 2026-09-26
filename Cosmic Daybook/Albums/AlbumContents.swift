// AlbumContents.swift
// What the library keeps from an album PDF as plain values, read once when
// the library loads so the PDF itself need not stay open.

import Foundation
import PDFKit

/// The page count, outline, lessons and identity fingerprint of one album
/// PDF. `Album` keeps these and closes the file; whatever needs the pages (a
/// reader, an export, a match thumbnail) opens it again through
/// `Album.document`.
struct AlbumContents {
    let pageCount: Int
    let outline: [AlbumOutlineNode]
    /// The outline flattened, in page order (depth breaks ties).
    let lessons: [AlbumLessonRef]
    /// See `AlbumIdentityRepair.fingerprint`.
    let fingerprint: String

    /// Reads one album, or nil if the file isn't a PDF PDFKit can open. The
    /// pool frees the parsed outline and pages before the next album opens.
    static func read(url: URL) -> AlbumContents? {
        autoreleasepool { () -> AlbumContents? in
            guard let document = PDFDocument(url: url) else { return nil }
            var flat: [AlbumLessonRef] = []
            let outline = document.outlineRoot.map {
                Self.nodes(under: $0, in: document, depth: 0, path: "r", flat: &flat)
            } ?? []
            let lessons = flat.sorted {
                $0.pageIndex == $1.pageIndex ? $0.depth < $1.depth : $0.pageIndex < $1.pageIndex
            }
            let fingerprint = AlbumIdentityRepair.fingerprint(
                pageCount: document.pageCount,
                lessonTitles: lessons.map(\.title),
                firstPageText: document.page(at: 0)?.string ?? "")
            return AlbumContents(pageCount: document.pageCount, outline: outline,
                                 lessons: lessons, fingerprint: fingerprint)
        }
    }

    /// The outline entries under `outline`, each also appended to `flat` as a
    /// lesson reference ahead of its children.
    private static func nodes(under outline: PDFOutline, in document: PDFDocument, depth: Int,
                              path: String, flat: inout [AlbumLessonRef]) -> [AlbumOutlineNode] {
        var nodes: [AlbumOutlineNode] = []
        for i in 0..<outline.numberOfChildren {
            guard let child = outline.child(at: i) else { continue }
            let title = (child.label ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
            var pageIndex = 0
            if let page = child.destination?.page { pageIndex = document.index(for: page) }
            let nodePath = "\(path).\(i)"
            var node = AlbumOutlineNode(id: nodePath, title: title, pageIndex: pageIndex, children: nil)
            flat.append(AlbumLessonRef(title: title, pageIndex: pageIndex, depth: depth))
            if child.numberOfChildren > 0 {
                node.children = Self.nodes(under: child, in: document, depth: depth + 1,
                                           path: nodePath, flat: &flat)
            }
            nodes.append(node)
        }
        return nodes
    }
}
