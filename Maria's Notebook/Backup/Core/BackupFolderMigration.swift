import Foundation
import OSLog

/// Detects when an existing user-picked backup folder lives in a suspicious
/// location (source repo, app bundle, system folder) and helps move the
/// existing `.mtbbackup` files into the managed iCloud folder.
///
/// Surfaced via the Settings UI as a one-time alert. Tracks dismissal via
/// `UserDefaults` so the user is never re-prompted after they explicitly
/// chose "Keep using this folder".
enum BackupFolderMigration {
    private static let logger = Logger.backup
    private static let dismissedKey = "Backup.folderMigration.dismissed"

    struct Prompt: Identifiable, Equatable {
        let id = UUID()
        let suspiciousFolder: URL
        let fileCount: Int
    }

    enum MoveResult {
        case moved(count: Int, destination: URL)
        case nothingToMove
        case failed(Error)
    }

    /// Returns a `Prompt` when:
    /// - A custom bookmark is set
    /// - That bookmark points to a folder that fails validation
    /// - The user has not already chosen to keep using it
    static func pendingPrompt() -> Prompt? {
        guard !UserDefaults.standard.bool(forKey: dismissedKey) else { return nil }
        guard let folder = BackupDestination.bookmarkedFolderNeedsMigration() else { return nil }

        let count = countBackupFiles(in: folder)
        return Prompt(suspiciousFolder: folder, fileCount: count)
    }

    /// User chose "Keep using this folder" — suppress future prompts.
    static func dismiss() {
        UserDefaults.standard.set(true, forKey: dismissedKey)
    }

    /// Re-enable the prompt (used in tests; not wired into UI).
    static func resetDismissal() {
        UserDefaults.standard.removeObject(forKey: dismissedKey)
    }

    /// Moves all `.mtbbackup` files from the suspicious folder into the
    /// managed iCloud folder, then clears the bookmark. Originals are
    /// deleted only after each copy succeeds; if copying fails for a file,
    /// that file is left in place.
    @discardableResult
    static func moveBackupsToManagedFolder(from sourceFolder: URL) async -> MoveResult {
        let needsAccess = sourceFolder.startAccessingSecurityScopedResource()
        defer { if needsAccess { sourceFolder.stopAccessingSecurityScopedResource() } }

        let fm = FileManager.default
        let destination: URL
        do {
            destination = try BackupFolderStorage.managedBackupsDirectory()
        } catch {
            logger.error("Failed to resolve managed backup folder: \(error.localizedDescription)")
            return .failed(error)
        }

        let backupURLs = backupFileURLs(in: sourceFolder)
        guard !backupURLs.isEmpty else {
            BackupDestination.clearDefaultFolder()
            dismiss()
            return .nothingToMove
        }

        var movedCount = 0
        for source in backupURLs {
            let target = uniqueDestination(in: destination, basedOn: source.lastPathComponent)
            do {
                try fm.copyItem(at: source, to: target)
                try? fm.removeItem(at: source)
                movedCount += 1
            } catch {
                let name = source.lastPathComponent
                let desc = error.localizedDescription
                logger.warning("Failed to move \(name, privacy: .public): \(desc, privacy: .public)")
            }
        }

        BackupDestination.clearDefaultFolder()
        dismiss()
        return .moved(count: movedCount, destination: destination)
    }

    // MARK: - Private

    private static func backupFileURLs(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }
        return entries.filter { $0.pathExtension == BackupFile.fileExtension }
    }

    private static func countBackupFiles(in folder: URL) -> Int {
        backupFileURLs(in: folder).count
    }

    private static func uniqueDestination(in folder: URL, basedOn filename: String) -> URL {
        let candidate = folder.appendingPathComponent(filename)
        guard FileManager.default.fileExists(atPath: candidate.path) else { return candidate }

        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var attempt = 2
        while true {
            let suffixed = "\(stem) (\(attempt))\(ext.isEmpty ? "" : ".\(ext)")"
            let url = folder.appendingPathComponent(suffixed)
            if !FileManager.default.fileExists(atPath: url.path) { return url }
            attempt += 1
        }
    }
}
