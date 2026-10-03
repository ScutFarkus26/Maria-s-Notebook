// AlbumPageTextReader.swift
// Reads an album PDF's page text for the full-text index without keeping every
// page it has read in memory.

import Foundation
import PDFKit

/// Every page's text from an album PDF, normalized (`AlbumLibrary.normalize`)
/// and in page order, as the full-text index stores it.
///
/// PDFKit keeps each page it has read, text layout and all, until its document
/// closes, so reading an album through one document grew by up to a megabyte
/// for each dense page: 500 dense generated pages peaked at 444 MB, enough to
/// get the iPad app jetsammed while it indexes. The pages are read through a
/// fresh opening of the file every `pagesPerOpening` pages instead (the same
/// 500 pages: 81 MB). The first opening decides the page count and is only
/// kept to fall back on, for any stretch where opening the file again fails
/// or finds a different number of pages.
nonisolated enum AlbumPageTextReader {
    static let pagesPerOpening = 50

    /// `open` opens the PDF; tests pass one that fails to test the fallback.
    static func pageTexts(url: URL, pagesPerOpening: Int = pagesPerOpening,
                          open: (URL) -> PDFDocument? = { PDFDocument(url: $0) }) -> [String] {
        guard let first = open(url) else { return [] }
        let pageCount = first.pageCount
        var texts: [String] = []
        texts.reserveCapacity(pageCount)
        while texts.count < pageCount {
            let pages = texts.count..<min(texts.count + max(pagesPerOpening, 1), pageCount)
            // The opening, its pages and their text layout go when the pool
            // drains, before the next stretch is opened.
            autoreleasepool {
                let reopened = open(url).flatMap { $0.pageCount == pageCount ? $0 : nil }
                let document = reopened ?? first
                for index in pages {
                    // A pool per page: what PDFKit autoreleases reading a page
                    // goes before the next page, not when the stretch is done.
                    texts.append(autoreleasepool { AlbumLibrary.normalize(document.page(at: index)?.string ?? "") })
                }
            }
        }
        return texts
    }
}
