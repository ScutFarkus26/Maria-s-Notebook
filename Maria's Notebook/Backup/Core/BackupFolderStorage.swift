import Foundation
import OSLog

/// The app's managed backup folder, visible in Files / Finder under
/// iCloud Drive › Maria's Notebook › Backups. Falls back to the local
/// app sandbox `Documents/Backups/` when iCloud is unavailable.
///
/// Mirrors the pattern used by `StoryFileStorage`, `LessonFileStorage`,
/// and `ResourceFileStorage` so manual exports land in a predictable,
/// user-visible location without requiring a security-scoped bookmark.
enum BackupFolderStorage {
    private static let logger = Logger.backup
    private static let folderName = "Backups"

    /// Returns the managed backup directory, creating it if needed.
    static func managedBackupsDirectory() throws -> URL {
        let fm = FileManager.default
        if let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) {
            let dir = ubiquityURL
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent(folderName, isDirectory: true)
            try createDirectoryIfNeeded(at: dir)
            return dir
        }
        logger.warning("iCloud unavailable; using local Documents for backups.")
        let local = try fm.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent(folderName, isDirectory: true)
        try createDirectoryIfNeeded(at: local)
        return local
    }

    /// Best-effort label for UI display. Returns the iCloud-relative path
    /// when applicable (e.g. "iCloud Drive › Maria's Notebook › Backups"),
    /// otherwise a local fallback label.
    static func displayLabel() -> String {
        guard let url = try? managedBackupsDirectory() else {
            return "Default Backups Folder"
        }
        let fm = FileManager.default
        if let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil),
           url.path.hasPrefix(ubiquityURL.path) {
            return "iCloud Drive › Maria's Notebook › \(folderName)"
        }
        return "Documents › \(folderName)"
    }

    private static func createDirectoryIfNeeded(at url: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: url.path) else { return }
        try fm.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
