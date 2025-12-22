import Foundation

#if os(macOS)
import AppKit
#endif

/// Stores and resolves the user's preferred default backup folder using bookmarks.
enum BackupDestination {
    private static let bookmarkKey = "Backup.defaultFolderBookmark"

    /// Save the chosen folder as a bookmark.
    static func setDefaultFolder(_ url: URL) throws {
        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif
        let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// Resolve the stored default folder URL from the bookmark.
    static func resolveDefaultFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif
        return try? URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
    }

    /// Clear any stored default folder.
    static func clearDefaultFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }
}
