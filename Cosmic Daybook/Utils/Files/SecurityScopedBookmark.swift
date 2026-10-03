//  SecurityScopedBookmark.swift
//  Cosmic Daybook
//
//  One place for the macOS/iOS split in security-scoped bookmarks.
//  macOS needs `.withSecurityScope` to keep sandbox access to a file the
//  guide picked; iOS has no such creation option and resolves without it.
//
//  This helper only creates and resolves. Starting and stopping access
//  (`startAccessingSecurityScopedResource()`) and deciding what a stale
//  bookmark means stay at the call site, where they belong.

import Foundation

nonisolated enum SecurityScopedBookmark {
    /// Resolves a stored bookmark, asking for security scope on macOS.
    /// - Parameters:
    ///   - data: the stored bookmark blob.
    ///   - options: extra resolution options (for example `.withoutUI`),
    ///     applied on both platforms alongside the platform's scope option.
    /// - Returns: the resolved URL and whether the bookmark was stale.
    static func resolve(
        _ data: Data,
        options: URL.BookmarkResolutionOptions = []
    ) throws -> (url: URL, isStale: Bool) {
        var isStale = false
        #if os(macOS)
        let resolutionOptions = options.union(.withSecurityScope)
        #else
        let resolutionOptions = options
        #endif
        let url = try URL(
            resolvingBookmarkData: data,
            options: resolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        return (url, isStale)
    }

    /// Creates a bookmark, asking for security scope on macOS.
    /// - Parameters:
    ///   - url: the file or folder to bookmark.
    ///   - unscopedOptions: creation options for platforms that have no
    ///     security-scoped creation option (iOS). macOS always writes a
    ///     plain `[.withSecurityScope]` bookmark, so a caller that wants a
    ///     `.minimalBookmark` on iOS still gets the full blob on the Mac.
    static func make(
        for url: URL,
        unscopedOptions: URL.BookmarkCreationOptions = []
    ) throws -> Data {
        #if os(macOS)
        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #else
        return try url.bookmarkData(
            options: unscopedOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        #endif
    }
}
