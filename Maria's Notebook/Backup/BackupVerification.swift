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
            
            // Read file
            let data = try Data(contentsOf: url)
            
            // Decode envelope
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let envelope: BackupEnvelope
            do {
                envelope = try decoder.decode(BackupEnvelope.self, from: data)
            } catch let decodingError as DecodingError {
                let errorMessage: String
                switch decodingError {
                case .dataCorrupted(let context):
                    errorMessage = "Backup file is corrupted or invalid JSON. "
                        + "\(context.debugDescription)"
                case .keyNotFound(let key, let context):
                    errorMessage = "Backup file is missing required field "
                        + "'\(key.stringValue)'. \(context.debugDescription)"
                case .typeMismatch(let type, let context):
                    errorMessage = "Backup file has invalid data type. "
                        + "Expected \(type), but found: "
                        + "\(context.debugDescription)"
                case .valueNotFound(let type, let context):
                    errorMessage = "Backup file is missing required value "
                        + "of type \(type). \(context.debugDescription)"
                @unknown default:
                    errorMessage = "Backup file format error: \(decodingError.localizedDescription)"
                }
                throw NSError(
                    domain: "BackupVerification", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: errorMessage]
                )
            } catch {
                throw NSError(
                    domain: "BackupVerification", code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Failed to decode backup file: "
                            + "\(error.localizedDescription)"
                    ]
                )
            }
            
            // Get file attributes
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = attributes[.size] as? Int64 ?? 0
            let modificationDate = attributes[.modificationDate] as? Date ?? Date()
            
            let info = BackupInfo(
                fileName: url.lastPathComponent,
                filePath: url.path,
                fileSize: fileSize,
                createdAt: envelope.createdAt,
                modifiedAt: modificationDate,
                formatVersion: envelope.formatVersion,
                appVersion: envelope.appVersion,
                appBuild: envelope.appBuild,
                device: envelope.device,
                isEncrypted: envelope.encryptedPayload != nil,
                isCompressed: envelope.compressedPayload != nil || envelope.manifest.compression != nil,
                entityCounts: envelope.manifest.entityCounts,
                checksum: envelope.manifest.sha256
            )
            
            return .success(info)
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
        
        // Check for auto-backups
        let autoBackupDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto")
        let autoBackupExists = FileManager.default.fileExists(atPath: autoBackupDir.path)
        
        var mostRecentAutoBackup: URL?
        if autoBackupExists {
            mostRecentAutoBackup = findMostRecentBackup(in: autoBackupDir)
        }
        
        return BackupStatus(
            lastBackupDate: lastBackupDate,
            autoBackupDirectoryExists: autoBackupExists,
            mostRecentAutoBackupURL: mostRecentAutoBackup
        )
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
