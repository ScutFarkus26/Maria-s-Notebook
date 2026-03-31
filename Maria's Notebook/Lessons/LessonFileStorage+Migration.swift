import Foundation
import OSLog
import CoreData

// MARK: - Migration

extension LessonFileStorage {

    // swiftlint:disable function_body_length
    /// Migrates files from the old private iCloud container location to the new public iCloud Drive location.
    /// This should be called once during app startup to move existing files to the user-visible location.
    /// - Returns: Number of files migrated, or nil if no migration was needed
    @discardableResult
    public static func migrateToICloudDrive() -> Int? {
        let fm = FileManager.default

        // Get the old location (private container - iCloud~AppID~/Documents/CDLesson Files/)
        guard let ubiquityURL = fm.url(forUbiquityContainerIdentifier: nil) else {
            logger.warning("No iCloud container available for migration")
            return nil
        }

        let oldLocation = ubiquityURL
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("CDLesson Files", isDirectory: true)

        // Check if old location exists and has files
        guard fm.fileExists(atPath: oldLocation.path) else {
            logger.info("No old files to migrate")
            return nil
        }

        do {
            // Get the new location (public iCloud Drive)
            let newLocation = try lessonFilesDirectory()

            // Check if they're the same (migration already done or not needed)
            if oldLocation.standardizedFileURL == newLocation.standardizedFileURL {
                logger.info("Already using new location, no migration needed")
                return nil
            }

            logger.info("Starting migration from old: \(oldLocation.path) to new: \(newLocation.path)")

            // Get all items in old location (recursively to handle Subject/Group folders)
            let contents = try fm.contentsOfDirectory(
                at: oldLocation,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
            var migratedCount = 0

            for oldItemURL in contents {
                let itemName = oldItemURL.lastPathComponent

                // Skip .DS_Store files
                if itemName == ".DS_Store" {
                    continue
                }

                let newItemURL = newLocation.appendingPathComponent(itemName)

                // Check if it's a directory or file
                let resourceValues = try oldItemURL.resourceValues(forKeys: [.isDirectoryKey])
                let isDirectory = resourceValues.isDirectory ?? false

                if isDirectory {
                    migratedCount += try migrateDirectoryContents(
                        from: oldItemURL,
                        to: newItemURL,
                        parentName: itemName
                    )
                } else {
                    if try migrateFile(from: oldItemURL, to: newItemURL, name: itemName) {
                        migratedCount += 1
                    }
                }
            }

            // Clean up empty directories in old location
            cleanUpEmptyDirectory(at: oldLocation)

            logger.info("Migration complete: \(migratedCount) files migrated")
            return migratedCount

        } catch {
            logger.error("Migration failed: \(error)")
            return nil
        }
    }
    // swiftlint:enable function_body_length

    // MARK: - Migration Helpers

    /// Migrates the contents of a subdirectory, creating the destination directory if needed.
    /// Returns the number of files successfully migrated.
    private static func migrateDirectoryContents(
        from sourceDir: URL,
        to destDir: URL,
        parentName: String
    ) throws -> Int {
        let fm = FileManager.default

        if !fm.fileExists(atPath: destDir.path) {
            try fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        }

        let subContents = try fm.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        var count = 0
        for subItemURL in subContents {
            let subItemName = subItemURL.lastPathComponent
            if subItemName == ".DS_Store" { continue }

            let newSubItemURL = destDir.appendingPathComponent(subItemName)
            if !fm.fileExists(atPath: newSubItemURL.path) {
                try fm.moveItem(at: subItemURL, to: newSubItemURL)
                logger.info("Migrated: \(parentName)/\(subItemName)")
                count += 1
            }
        }
        return count
    }

    /// Moves a single file if it does not already exist at the destination.
    /// Returns true if the file was migrated.
    private static func migrateFile(from source: URL, to destination: URL, name: String) throws -> Bool {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.path) {
            try fm.moveItem(at: source, to: destination)
            logger.info("Migrated: \(name)")
            return true
        } else {
            logger.info("Skipping \(name) - already exists at destination")
            return false
        }
    }

    /// Removes a directory if it contains only .DS_Store files (or is empty).
    private static func cleanUpEmptyDirectory(at url: URL) {
        let fm = FileManager.default
        do {
            let remainingContents = try fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let nonDSStoreContents = remainingContents.filter { $0.lastPathComponent != ".DS_Store" }
            if nonDSStoreContents.isEmpty {
                try fm.removeItem(at: url)
                logger.info("Removed empty old location")
            }
        } catch {
            logger.warning("Failed to remove old location: \(error)")
        }
    }
}
