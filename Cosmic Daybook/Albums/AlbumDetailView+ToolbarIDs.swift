// AlbumDetailView+ToolbarIDs.swift
// The customization ids of the album reader's Mac toolbar — one per kind of
// window, because AppKit couples every toolbar that shares an identifier.

#if os(macOS)
extension AlbumDetailView {
    /// The customization id when the album is read inside the main window.
    /// SwiftUI gives the *whole window's* toolbar this identifier, so that
    /// toolbar also carries the main window's own items (sidebar toggle,
    /// classroom, school year, search, sync status).
    static let readerToolbarID = "album"

    /// The customization id in a separate album window, whose toolbar holds the
    /// album items alone. It must differ from `readerToolbarID`: AppKit replays
    /// every insert and remove across all toolbars with the same identifier, so
    /// two toolbars sharing an id but not an item list drift apart, and the next
    /// change crashes the app on a duplicate item or an index past the end
    /// (2026-09-26: switching albums in the main window while an album window
    /// was open). Same-kind windows are safe — their item lists match.
    static let albumWindowToolbarID = "album-window"
}
#endif
