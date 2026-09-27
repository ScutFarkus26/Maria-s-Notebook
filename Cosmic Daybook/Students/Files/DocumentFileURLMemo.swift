// DocumentFileURLMemo.swift
// A document card's file, resolved once per bookmark value instead of on every redraw.

import Foundation

/// Remembers what `StudentDocumentFileStorage.resolveURL` answered for one
/// bookmark and relative path, so a card's redraws reuse the answer.
///
/// `DocumentCard` resolved its file on every body pass: a
/// `URL(resolvingBookmarkData:)` plus a `fileExists` check, and when the
/// bookmark no longer resolves, the relative-path fallback's iCloud container
/// lookup as well. Every redraw of the Files tab ran that once per card. The
/// card now keeps one of these in `@State`: the first read resolves exactly as
/// before, and later reads with the same bookmark and path return that answer —
/// nil for a missing file included — until either value changes.
///
/// Only the thumbnail reads it. Opening the document resolves afresh, as it
/// always did, so a file that has since moved, gone or arrived opens (or falls
/// back to the record's data) exactly as before.
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
        resolve: @MainActor (Data?, String) -> URL? = StudentDocumentFileStorage.resolveURL
    ) -> URL? {
        let key = Key(bookmark: bookmark, relativePath: relativePath)
        if key == self.key { return url }
        resolutionCount += 1
        url = resolve(bookmark, relativePath)
        self.key = key
        return url
    }
}
