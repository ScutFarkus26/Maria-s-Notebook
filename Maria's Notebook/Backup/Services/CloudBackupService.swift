// CloudBackupService.swift
// Handles iCloud Drive integration for backups

import Foundation

/// Service for managing backups in iCloud Drive
/// Provides automatic cloud sync for backup files without requiring manual file management
@MainActor
public final class CloudBackupService {

    // MARK: - Types

    public enum CloudBackupError: LocalizedError {
        case iCloudNotAvailable
        case containerNotFound
        case backupFailed(Error)
        case restoreFailed(Error)
        case fileNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .iCloudNotAvailable:
                return "iCloud is not available. Please sign in to iCloud in System Settings."
            case .containerNotFound:
                return "Could not access iCloud container. Please check iCloud Drive is enabled."
            case .backupFailed(let error):
                return "Backup to iCloud failed: \(error.localizedDescription)"
            case .restoreFailed(let error):
                return "Restore from iCloud failed: \(error.localizedDescription)"
            case .fileNotFound(let name):
                return "Backup file '\(name)' not found in iCloud."
            }
        }
    }

    public struct CloudBackupInfo: Identifiable, Sendable {
        public let id: UUID
        public let fileName: String
        public let fileURL: URL
        public let fileSize: Int64
        public let createdAt: Date
        public let modifiedAt: Date
        public let isDownloaded: Bool
        public let isUploading: Bool
        public let isDownloading: Bool

        public var formattedFileSize: String {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            formatter.allowedUnits = [.useKB, .useMB, .useGB]
            return formatter.string(fromByteCount: fileSize)
        }
    }

    // MARK: - Properties

    private let backupService = BackupService()
    private let fileManager = FileManager.default

    /// The iCloud Drive backup directory name
    private static let backupFolderName = "Backups"

    // MARK: - Public API

    /// Checks if iCloud Drive is available
    public var isICloudAvailable: Bool {
        fileManager.ubiquityIdentityToken != nil
    }

    /// Gets the iCloud backup directory URL
    public var cloudBackupDirectory: URL? {
        guard let containerURL = fileManager.url(forUbiquityContainerIdentifier: nil) else {
            return nil
        }
        return containerURL
            .appendingPathComponent("Documents")
            .appendingPathComponent(Self.backupFolderName)
    }

    /// Creates the cloud backup directory if it doesn't exist
    public func ensureCloudBackupDirectoryExists() throws {
        guard let cloudDir = cloudBackupDirectory else {
            throw CloudBackupError.containerNotFound
        }

        if !fileManager.fileExists(atPath: cloudDir.path) {
            try fileManager.createDirectory(at: cloudDir, withIntermediateDirectories: true)
        }
    }

    /// Exports a backup directly to iCloud Drive
    /// - Parameters:
    ///   - modelContext: The SwiftData model context
    ///   - password: Optional encryption password
    ///   - progress: Progress callback
    /// - Returns: The URL of the created backup file
    public func exportToCloud(
        modelContext: any Any,
        password: String? = nil,
        progress: @escaping (Double, String) -> Void
    ) async throws -> URL {
        guard isICloudAvailable else {
            throw CloudBackupError.iCloudNotAvailable
        }

        try ensureCloudBackupDirectoryExists()

        guard let cloudDir = cloudBackupDirectory else {
            throw CloudBackupError.containerNotFound
        }

        // Create timestamped filename
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-") // Make filesystem-safe
        let filename = "CloudBackup-\(timestamp).\(BackupFile.fileExtension)"
        let destinationURL = cloudDir.appendingPathComponent(filename)

        do {
            // Import SwiftData dynamically to avoid circular dependency
            guard let context = modelContext as? SwiftData.ModelContext else {
                throw CloudBackupError.backupFailed(NSError(
                    domain: "CloudBackupService",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Invalid model context type"]
                ))
            }

            _ = try await backupService.exportBackup(
                modelContext: context,
                to: destinationURL,
                password: password,
                progress: progress
            )

            // Trigger iCloud upload
            try fileManager.startDownloadingUbiquitousItem(at: destinationURL)

            return destinationURL
        } catch {
            throw CloudBackupError.backupFailed(error)
        }
    }

    /// Lists all backups available in iCloud Drive
    /// - Returns: Array of cloud backup info sorted by date (newest first)
    public func listCloudBackups() async throws -> [CloudBackupInfo] {
        guard isICloudAvailable else {
            throw CloudBackupError.iCloudNotAvailable
        }

        guard let cloudDir = cloudBackupDirectory else {
            throw CloudBackupError.containerNotFound
        }

        // Ensure directory exists
        if !fileManager.fileExists(atPath: cloudDir.path) {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .nameKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .ubiquitousItemDownloadingStatusKey,
            .ubiquitousItemIsUploadingKey,
            .ubiquitousItemIsDownloadingKey
        ]

        guard let enumerator = fileManager.enumerator(
            at: cloudDir,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return []
        }

        var backups: [CloudBackupInfo] = []

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == BackupFile.fileExtension else { continue }

            do {
                let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)

                // Check download status using the downloading status key
                let downloadStatus = resourceValues.ubiquitousItemDownloadingStatus
                let isDownloaded = downloadStatus == .current || downloadStatus == nil

                let info = CloudBackupInfo(
                    id: UUID(),
                    fileName: resourceValues.name ?? fileURL.lastPathComponent,
                    fileURL: fileURL,
                    fileSize: Int64(resourceValues.fileSize ?? 0),
                    createdAt: resourceValues.creationDate ?? Date.distantPast,
                    modifiedAt: resourceValues.contentModificationDate ?? Date.distantPast,
                    isDownloaded: isDownloaded,
                    isUploading: resourceValues.ubiquitousItemIsUploading ?? false,
                    isDownloading: resourceValues.ubiquitousItemIsDownloading ?? false
                )
                backups.append(info)
            } catch {
                // Skip files that can't be read
                continue
            }
        }

        // Sort by modification date (newest first)
        return backups.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Downloads a backup from iCloud if not already downloaded
    /// - Parameter backup: The backup to download
    /// - Returns: The local URL once downloaded
    public func downloadBackupIfNeeded(_ backup: CloudBackupInfo) async throws -> URL {
        guard isICloudAvailable else {
            throw CloudBackupError.iCloudNotAvailable
        }

        if backup.isDownloaded {
            return backup.fileURL
        }

        // Start download
        try fileManager.startDownloadingUbiquitousItem(at: backup.fileURL)

        // Wait for download to complete (poll every 0.5 seconds, timeout after 60 seconds)
        let timeout = Date().addingTimeInterval(60)
        while Date() < timeout {
            let resourceValues = try backup.fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if resourceValues.ubiquitousItemDownloadingStatus == .current {
                return backup.fileURL
            }
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        throw CloudBackupError.fileNotFound(backup.fileName)
    }

    /// Deletes a backup from iCloud Drive
    /// - Parameter backup: The backup to delete
    public func deleteCloudBackup(_ backup: CloudBackupInfo) throws {
        guard fileManager.fileExists(atPath: backup.fileURL.path) else {
            throw CloudBackupError.fileNotFound(backup.fileName)
        }

        try fileManager.removeItem(at: backup.fileURL)
    }

    /// Applies retention policy to cloud backups
    /// - Parameter maxCount: Maximum number of backups to keep
    public func applyRetentionPolicy(maxCount: Int) async throws {
        let backups = try await listCloudBackups()

        if backups.count > maxCount {
            // Delete oldest backups that exceed the count
            let backupsToDelete = backups.suffix(backups.count - maxCount)
            for backup in backupsToDelete {
                try? deleteCloudBackup(backup)
            }
        }
    }

    /// Copies a local backup to iCloud Drive
    /// - Parameter localURL: The local backup file URL
    /// - Returns: The iCloud URL of the copied file
    public func copyToCloud(_ localURL: URL) throws -> URL {
        guard isICloudAvailable else {
            throw CloudBackupError.iCloudNotAvailable
        }

        try ensureCloudBackupDirectoryExists()

        guard let cloudDir = cloudBackupDirectory else {
            throw CloudBackupError.containerNotFound
        }

        let destinationURL = cloudDir.appendingPathComponent(localURL.lastPathComponent)

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: localURL, to: destinationURL)

        return destinationURL
    }
}

import SwiftData
