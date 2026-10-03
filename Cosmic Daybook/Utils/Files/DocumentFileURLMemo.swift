// DocumentFileURLMemo.swift
// A stored document's file, resolved once per stored value instead of on every redraw.

import Foundation

/// Remembers where a stored document's file was found, so a screen's
/// redraws reuse the answer instead of resolving it again.
///
/// Three screens resolved a stored file inside `body`, so every redraw paid
/// for it: the Student Files card (its thumbnail), the Book Club packet
/// detail (whether Open PDF is enabled; every keystroke in the packet's
/// fields redraws it) and the resource detail (whether Share and Print are
/// offered, and what Share sends). A resolution is a bookmark resolution and
/// a `fileExists` check, and when the bookmark no longer finds the file, the
/// managed folder's lookup and another check for the relative path (see
/// `ManagedPDFFileStorage`).
///
/// A screen keeps one of these in `@State` and reads through it with its
/// library's resolver. The first read resolves exactly as before; later reads
/// with the same bookmark and relative path return that answer, nil for a
/// missing file included, until either value changes.
///
/// Opening, deleting and printing a document resolve afresh, as they always
/// did, so a file that has since moved, gone or arrived is found (or not)
/// exactly as before.
final class DocumentFileURLMemo {

    private struct Key: Equatable {
        let bookmark: Data?
        let relativePath: String
    }

    private var key: Key?
    private var url: URL?
    /// How many times it has resolved (for tests pinning the memo).
    private(set) var resolutionCount = 0

    /// The file for `bookmark` and `relativePath`: the remembered answer when
    /// both match the last read, otherwise `resolve`'s, remembered.
    func url(
        bookmark: Data?,
        relativePath: String,
        resolve: @MainActor (Data?, String) -> URL?
    ) -> URL? {
        let key = Key(bookmark: bookmark, relativePath: relativePath)
        if key == self.key { return url }
        resolutionCount += 1
        url = resolve(bookmark, relativePath)
        self.key = key
        return url
    }

    /// The same, for a library that keeps only a relative path (Resources).
    func url(relativePath: String, resolve: @MainActor (String) -> URL?) -> URL? {
        url(bookmark: nil, relativePath: relativePath) { _, path in resolve(path) }
    }
}
