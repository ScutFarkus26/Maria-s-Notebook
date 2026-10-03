// Album.swift
// Album stands for one PDF: its outline and lessons (read once by AlbumContents),
// cover rendering, highlight annotations, and the document itself, opened on use
// and let go by memory trims.

import CoreData
import SwiftUI
import PDFKit

// PlatformImage comes from Albums/Detail/PrintUtils.swift; PlatformColor from
// ParentReports/Services/ReportGeneratorService.swift.

@Observable
final class Album: Identifiable {
    let id: String            // filename, e.g. "Biology Album.pdf"
    let url: URL
    let title: String
    let subject: AlbumSubject
    let pageCount: Int
    let outline: [AlbumOutlineNode]
    let lessons: [AlbumLessonRef]  // flattened outline in document order
    /// Content fingerprint, used to recognise this album again after the PDF
    /// is renamed or moved. Read at load, while the PDF is open for its outline.
    let fingerprint: String
    var cover: PlatformImage?
    var coverRequested = false

    /// The PDF, opened on first use and held until `releaseDocument()`. It is
    /// what a reader shows and what Find and highlighting fill in with page
    /// objects and page text, so an album read once used to stay that big.
    @ObservationIgnored private var heldDocument: PDFDocument?
    /// The same PDF for as long as anything else still has it, a reader's
    /// PDFView, so a release never swaps it out from under a reader.
    @ObservationIgnored private weak var openDocument: PDFDocument?

    init?(url: URL) {
        // Only values are kept; the PDF closes here and reopens on first use.
        guard let contents = AlbumContents.read(url: url) else { return nil }
        self.id = url.lastPathComponent
        self.url = url
        self.title = Album.cleanTitle(from: url)
        self.subject = AlbumSubject.detect(from: title)
        self.pageCount = contents.pageCount
        self.outline = contents.outline
        self.lessons = contents.lessons
        self.fingerprint = contents.fingerprint
    }

    static func cleanTitle(from url: URL) -> String {
        var t = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespaces)
        t = t.replacingOccurrences(of: " Album", with: "")
            .trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? url.deletingPathExtension().lastPathComponent : t
    }

    /// The album's PDF for a reader, an export or a page thumbnail: opened on
    /// first use and kept until `releaseDocument()`. Nil only when the file
    /// can no longer be opened (moved or deleted since the library loaded).
    var document: PDFDocument? {
        if let heldDocument { return heldDocument }
        let document = openDocument ?? PDFDocument(url: url)
        heldDocument = document
        openDocument = document
        return document
    }

    /// Lets go of the PDF, as a memory trim does. It closes once nothing else
    /// has it (at once for an album no reader is showing) and the next use
    /// reopens the file; a reader still showing it keeps that same document.
    func releaseDocument() {
        heldDocument = nil
    }

    /// Number of leaf outline entries — a decent proxy for "lessons".
    var lessonCount: Int {
        func leaves(_ nodes: [AlbumOutlineNode]) -> Int {
            nodes.reduce(0) { $0 + (($1.children?.isEmpty ?? true) ? 1 : leaves($1.children!)) }
        }
        return leaves(outline)
    }

    /// The deepest outline entry at or before the given page.
    func lesson(forPage pageIndex: Int) -> AlbumLessonRef? {
        lessons.last { $0.pageIndex <= pageIndex }
    }

    /// The page range covered by the lesson segment containing `pageIndex`
    /// (from its outline entry to the next outline entry in document order).
    func lessonRange(forPage pageIndex: Int) -> ClosedRange<Int> {
        guard let current = lesson(forPage: pageIndex) else { return pageIndex...pageIndex }
        let next = lessons.first { $0.pageIndex > current.pageIndex }
        let end = (next?.pageIndex).map { max(current.pageIndex, $0 - 1) } ?? (pageCount - 1)
        return current.pageIndex...min(end, pageCount - 1)
    }

    // MARK: CDAlbumHighlight rendering

    /// One annotation we've injected into the open document (never written
    /// back to the PDF file). Weak: its page owns it, and once the document
    /// closes there is nothing left to take off.
    private struct AppliedHighlight {
        weak var annotation: PDFAnnotation?
        weak var page: PDFPage?
    }

    /// The injected annotations, so they can be cleanly replaced.
    private var appliedHighlightAnnotations: [AppliedHighlight] = []

    func applyHighlights(_ items: [CDAlbumHighlight]) {
        for entry in appliedHighlightAnnotations {
            if let annotation = entry.annotation, let page = entry.page {
                page.removeAnnotation(annotation)
            }
        }
        appliedHighlightAnnotations = []
        guard let document else { return }
        for item in items {
            guard let page = document.page(at: Int(item.pageIndex)) else { continue }
            for rect in item.rects {
                let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
                annotation.color = Album.highlightColor(item.colorName).withAlphaComponent(0.45)
                let local = [CGPoint(x: 0, y: rect.height),
                             CGPoint(x: rect.width, y: rect.height),
                             CGPoint(x: 0, y: 0),
                             CGPoint(x: rect.width, y: 0)]
                #if os(macOS)
                annotation.quadrilateralPoints = local.map { NSValue(point: $0) }
                #else
                annotation.quadrilateralPoints = local.map { NSValue(cgPoint: $0) }
                #endif
                page.addAnnotation(annotation)
                appliedHighlightAnnotations.append(AppliedHighlight(annotation: annotation, page: page))
            }
        }
    }

    static func highlightColor(_ name: String) -> PlatformColor {
        switch name {
        case "green": .systemGreen
        case "blue": .systemBlue
        case "pink": .systemPink
        default: .systemYellow
        }
    }
}
