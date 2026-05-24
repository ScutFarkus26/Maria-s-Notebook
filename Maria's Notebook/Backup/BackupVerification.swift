import Foundation
import CoreData
import OSLog

/// Utility to verify backup file integrity and provide status information
@MainActor
public struct BackupVerification {
    private static let logger = Logger.backup
    
    // Verifies a backup file by attempting to read and decode its envelope
    // Returns information about the backup if valid, or an error if invalid
    // swiftlint:disable:next function_body_length
    public static func verifyBackup(at url: URL) -> Result<BackupInfo, Error> {
        do {
            // Check file exists
            guard FileManager.default.fileExists(atPath: url.path) else {
                return .failure(NSError(
                    domain: "BackupVerification",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Backup file does not exist at path: \(url.path)"]
                ))
            }

            if BackupArchive.isAEAFormat(at: url) {
                return .success(try verifyAEAFormat(at: url))
            }

            return .failure(NSError(
                domain: "BackupVerification",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Legacy .mtbbackup files are no longer supported. Verify or import a current backup created by this version of the app."
                ]
            ))
        } catch {
            return .failure(error)
        }
    }
    
    /// Finds the most recent backup file in a directory
    public static func findMostRecentBackup(in directory: URL) -> URL? {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            logger.warning("Failed to list directory contents: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        
        let backupFiles = files.filter { $0.pathExtension == BackupFile.fileExtension }
        
        guard !backupFiles.isEmpty else {
            return nil
        }
        
        // Sort by modification date (most recent first)
        let sorted = backupFiles.sorted { url1, url2 in
            let date1: Date
            do {
                date1 = try url1.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate ?? Date.distantPast
            } catch {
                let name = url1.lastPathComponent
                let desc = error.localizedDescription
                logger.warning("Failed to get mod date for \(name, privacy: .public): \(desc, privacy: .public)")
                date1 = Date.distantPast
            }
            
            let date2: Date
            do {
                date2 = try url2.resourceValues(
                    forKeys: [.contentModificationDateKey]
                ).contentModificationDate ?? Date.distantPast
            } catch {
                let name = url2.lastPathComponent
                let desc = error.localizedDescription
                logger.warning("Failed to get mod date for \(name, privacy: .public): \(desc, privacy: .public)")
                date2 = Date.distantPast
            }
            
            return date1 > date2
        }
        
        return sorted.first
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
        let mostRecentAutoBackup = directories
            .compactMap(findMostRecentBackup(in:))
            .max { lhs, rhs in
                let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey])
                    .contentModificationDate) ?? .distantPast
                return lhsDate < rhsDate
            }

        return BackupStatus(
            lastBackupDate: lastBackupDate,
            autoBackupDirectoryExists: autoBackupDirectoryExists,
            mostRecentAutoBackupURL: mostRecentAutoBackup
        )
    }

    private static func verifyAEAFormat(at url: URL) throws -> BackupInfo {
        let decoded = try BackupReader.read(from: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let modificationDate = attributes[.modificationDate] as? Date ?? Date()

        return BackupInfo(
            fileName: url.lastPathComponent,
            filePath: url.path,
            fileSize: fileSize,
            createdAt: decoded.manifest.createdAt,
            modifiedAt: modificationDate,
            formatVersion: decoded.manifest.formatVersion,
            appVersion: decoded.manifest.appVersion,
            appBuild: decoded.manifest.appBuild,
            device: decoded.manifest.device,
            isEncrypted: false,
            isCompressed: true,
            entityCounts: decoded.manifest.entityCounts,
            checksum: "AEA/LZFSE archive"
        )
    }

    private static func autoBackupDirectories() -> [URL] {
        var directories: [URL] = []
        if let userFolder = BackupDestination.resolveDefaultFolder() {
            directories.append(userFolder.appendingPathComponent("Auto", isDirectory: true))
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
    
    public var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: fileSize)
    }
    
    public var totalEntityCount: Int {
        entityCounts.values.reduce(0, +)
    }
}

/// Status information about backups
public struct BackupStatus {
    public let lastBackupDate: Date?
    public let autoBackupDirectoryExists: Bool
    public let mostRecentAutoBackupURL: URL?
}
