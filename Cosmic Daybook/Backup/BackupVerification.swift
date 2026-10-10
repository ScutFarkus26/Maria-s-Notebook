import Foundation
import CoreData
import OSLog

/// Utility to verify backup file integrity and provide status information
public struct BackupVerification {
    private static let logger = Logger.backup
    
    // Verifies a backup file by streaming the whole archive: the manifest must
    // decode, every entity entry must parse, and per-entry NDJSON row counts
    // must match the manifest. Full container integrity (decrypt/decompress)
    // without JSON-decoding every record or holding the payload in memory.
    public static func verifyBackup(at url: URL) -> Result<BackupInfo, Error> {
        do {
            // Check file exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .failure(NSError(
                    domain: "BackupVerification",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "Couldn't find that backup file. It may have been moved or deleted."
                    ]
                ))
            }

            if BackupArchive.isBackupArchive(at: url) {
                return .success(try verifyArchive(at: url))
            }

            return .failure(NSError(
                domain: "BackupVerification",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "This backup is from an old version of the app and can't be restored. " +
                        "Choose a newer backup."
                ]
            ))
        } catch {
            return .failure(error)
        }
    }
    
    /// Gets backup status information including last backup date from UserDefaults
    public static func getBackupStatus() -> BackupStatus {
        let lastBackupKey = "LastBackupTimeInterval"
        let timestamp = UserDefaults.standard.double(forKey: lastBackupKey)
        let lastBackupDate = timestamp > 0 ? Date(timeIntervalSinceReferenceDate: timestamp) : nil

        let directories = autoBackupDirectories()
        let autoBackupDirectoryExists = directories.contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
        // Any device's: each writes to a folder of its own inside `Auto/`, and
        // older builds wrote at its top (`AutoBackupFolders`).
        let mostRecentAutoBackup = AutoBackupFolders.mostRecentBackup(in: directories)

        return BackupStatus(
            lastBackupDate: lastBackupDate,
            autoBackupDirectoryExists: autoBackupDirectoryExists,
            mostRecentAutoBackupURL: mostRecentAutoBackup
        )
    }

    private static func verifyArchive(at url: URL) throws -> BackupInfo {
        let verification = try BackupReader.verifyStructure(at: url)
        let manifest = verification.manifest

        // The manifest's promised per-entity counts must match what's actually
        // in the file — a truncated or tampered archive fails here.
        for (entityName, expected) in manifest.entityCounts {
            let actual = verification.entryLineCounts[entityName] ?? 0
            guard actual == expected else {
                logger.error(
                    "Backup damaged: \(entityName, privacy: .public) promises \(expected) rows, holds \(actual)"
                )
                throw NSError(
                    domain: "BackupVerification",
                    code: 3,
                    userInfo: [
                        NSLocalizedDescriptionKey: BackupArchive.ArchiveError.damaged
                    ]
                )
            }
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()
        let isEncrypted = BackupArchive.isEncryptedArchive(at: url)

        return BackupInfo(
            fileName: url.lastPathComponent,
            filePath: url.path,
            fileSize: fileSize,
            createdAt: manifest.createdAt,
            modifiedAt: modificationDate,
            formatVersion: manifest.formatVersion,
            appVersion: manifest.appVersion,
            appBuild: manifest.appBuild,
            device: manifest.device,
            isEncrypted: isEncrypted,
            isCompressed: true,
            entityCounts: manifest.entityCounts,
            checksum: isEncrypted ? "AEA (AES-CTR + HMAC)" : "LZFSE archive"
        )
    }

    private static func autoBackupDirectories() -> [URL] {
        var directories: [URL] = []
        if let userFolder = BackupDestination.resolveDefaultFolder() {
            directories.append(userFolder.appendingPathComponent(AutoBackupFolders.autoFolderName, isDirectory: true))
        }
        let fallback = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto", isDirectory: true)
        directories.append(fallback)
        return directories
    }
}

/// Information about a verified backup file
public struct BackupInfo {
    public let fileName: String
    public let filePath: String
    public let fileSize: Int64
    public let createdAt: Date
    public let modifiedAt: Date
    public let formatVersion: Int
    public let appVersion: String
    public let appBuild: String
    public let device: String
    public let isEncrypted: Bool
    public let isCompressed: Bool
    public let entityCounts: [String: Int]
    public let checksum: String
    
}

/// Status information about backups
public struct BackupStatus {
    public let lastBackupDate: Date?
    public let autoBackupDirectoryExists: Bool
    public let mostRecentAutoBackupURL: URL?
}
