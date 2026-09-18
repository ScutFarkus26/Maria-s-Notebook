import Foundation
import OSLog

#if os(macOS)
import AppKit
#endif

/// Stores and resolves the user's preferred default backup folder using bookmarks.
///
/// Resolution is three-tiered:
/// 1. A user-picked folder (if a valid bookmark exists)
/// 2. The app's managed iCloud Drive folder (`BackupFolderStorage`)
/// 3. `nil` (only when both above fail; callers fall back to a save dialog)
enum BackupDestination {
    private static let logger = Logger.backup
    private static let bookmarkKey = "Backup.defaultFolderBookmark"

    /// Reasons a user-picked folder may be rejected.
    enum FolderRejection: LocalizedError {
        case insideGitRepository(URL)
        case insideAppBundle(URL)
        case systemProtected(URL)

        var errorDescription: String? {
            switch self {
            case .insideGitRepository(let url):
                return "“\(url.lastPathComponent)” is inside a code repository. " +
                       "Backups would be tracked in version control."
            case .insideAppBundle(let url):
                return "“\(url.lastPathComponent)” is inside an app or Xcode project bundle. " +
                       "Files there can be lost when the app is rebuilt or reinstalled."
            case .systemProtected:
                return "That folder is in a system-protected location. " +
                       "Choose a folder in your Documents or iCloud Drive."
            }
        }
    }

    // MARK: - Setting / Clearing

    /// Save the chosen folder as a bookmark after validating it isn't a
    /// suspicious location (source repo, app bundle, system folder).
    static func setDefaultFolder(_ url: URL) throws {
        try validateFolder(url)

        #if os(macOS)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkCreationOptions = []
        #endif

        let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    /// Clear any stored default folder. Future exports fall back to the
    /// managed iCloud folder.
    static func clearDefaultFolder() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    // MARK: - Resolution

    /// Resolve the destination for manual exports. Returns the user-picked
    /// folder when set, otherwise the managed iCloud folder.
    static func resolveDefaultFolder() -> URL? {
        if let bookmarked = resolveBookmarkedFolder() { return bookmarked }
        return try? BackupFolderStorage.managedBackupsDirectory()
    }

    /// Returns the user-picked folder only — nil when none has been set.
    /// Used by migration logic to detect whether a custom folder is in use.
    static func resolveBookmarkedFolder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false

        #if os(macOS)
        let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = []
        #endif

        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )

            if stale {
                logger.debug("Bookmark is stale. Refreshing...")
                do {
                    try setDefaultFolder(url)
                } catch {
                    logger.warning("Failed to refresh stale bookmark: \(error)")
                }
            }
            return url
        } catch let error as NSError where
            error.domain == NSCocoaErrorDomain && error.code == NSFileReadCorruptFileError {
            // Bookmark blob is corrupt or in a format we no longer understand
            // (e.g. saved by an older build without security scope). Evict it
            // so we stop spamming the log every time someone touches backups,
            // and fall back to the managed iCloud folder.
            logger.warning("Backup folder bookmark is corrupt; clearing it.")
            clearDefaultFolder()
            return nil
        } catch {
            logger.debug("Failed to resolve backup folder bookmark: \(error)")
            return nil
        }
    }

    /// True when a user-picked bookmark exists and points to a folder that
    /// would now be rejected by `validateFolder`. Drives the one-time
    /// migration prompt that helps users move existing backups.
    static func bookmarkedFolderNeedsMigration() -> URL? {
        guard let url = resolveBookmarkedFolder() else { return nil }
        do {
            try validateFolder(url)
            return nil
        } catch {
            return url
        }
    }

    // MARK: - Validation

    /// Throws `FolderRejection` if the URL points to a suspicious location.
    private static func validateFolder(_ url: URL) throws {
        let fm = FileManager.default

        if url.path.hasPrefix("/System/") || url.path.hasPrefix("/private/var/") {
            throw FolderRejection.systemProtected(url)
        }

        // Walk up parent directories looking for .git or a bundle extension.
        var dir = url.standardizedFileURL
        while dir.path != "/" {
            if dir.pathExtension == "app" || dir.pathExtension == "xcodeproj" {
                throw FolderRejection.insideAppBundle(dir)
            }
            let gitPath = dir.appendingPathComponent(".git")
            if fm.fileExists(atPath: gitPath.path) {
                throw FolderRejection.insideGitRepository(dir)
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
    }
}
