// swiftlint:disable file_length
// CloudBackupService.swift
// Handles iCloud Drive integration for backups

import Foundation
import SwiftData
import OSLog

// swiftlint:disable type_body_length
/// Service for managing backups in iCloud Drive
/// Provides automatic cloud sync for backup files without requiring manual file management
@Observable
@MainActor
public final class CloudBackupService {
    static let logger = Logger.backup

    // MARK: - Types

    /// Modern event-based notification for cloud backup operations
    public enum CloudBackupEventResult: Sendable {
        case completed(URL)
        case failed(Error)
    }

    public struct CloudBackupEvent: Sendable {
        public let timestamp: Date
        public let result: CloudBackupEventResult
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

    // MARK: - Observable State

    public var isPerformingBackup = false
    public var lastCloudBackupDate: Date?
    public var nextScheduledBackupDate: Date?
    public var currentRetryAttempt: Int = 0

    /// Modern event stream - SwiftUI views can observe this
    public var lastBackupEvent: CloudBackupEvent?

    // MARK: - Properties

    let backupService: BackupService
    let fileManager = FileManager.default

    /// The iCloud Drive backup directory name
    private static let backupFolderName = "Backups"

    /// Retry configuration
    public var retryConfiguration = RetryConfiguration.default

    /// Schedule configuration (persisted in UserDefaults)
    public var scheduleConfiguration: ScheduleConfiguration {
        get {
            if let data = UserDefaults.standard.data(forKey: "CloudBackup.scheduleConfig") {
                do {
                    let config = try JSONDecoder().decode(ScheduleConfiguration.self, from: data)
                    return config
                } catch {
                    let desc = error.localizedDescription
                    Self.logger.warning("Failed to decode schedule configuration: \(desc, privacy: .public)")
                }
            }
            return .default
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(data, forKey: "CloudBackup.scheduleConfig")
            } catch {
                let desc = error.localizedDescription
                Self.logger.warning("Failed to encode schedule configuration: \(desc, privacy: .public)")
            }
            updateScheduledBackups()
        }
    }

    /// Scheduled backup task
    var scheduledBackupTask: Task<Void, Never>?

    /// Model context for scheduled backups
    var scheduledModelContext: ModelContext?

    // MARK: - UserDefaults Keys

    enum Keys {
        static let lastCloudBackupDate = "CloudBackup.lastBackupDate"
        static let scheduleConfig = "CloudBackup.scheduleConfig"
    }

    // MARK: - Validation Helpers

    /// Ensures iCloud is available, throwing if not
    func requireICloudAvailable() throws {
        guard isICloudAvailable else {
            throw BackupOperationError.cloudOperationFailed(.iCloudNotAvailable)
        }
    }

    /// Returns the cloud backup directory URL, throwing if not available
    func requireCloudDirectory() throws -> URL {
        guard let cloudDir = cloudBackupDirectory else {
            throw BackupOperationError.cloudOperationFailed(.containerNotFound)
        }
        return cloudDir
    }

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
            throw BackupOperationError.cloudOperationFailed(.containerNotFound)
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
        modelContext: ModelContext,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> URL {
        guard isICloudAvailable else {
            throw BackupOperationError.cloudOperationFailed(.iCloudNotAvailable)
        }

        try ensureCloudBackupDirectoryExists()

        guard let cloudDir = cloudBackupDirectory else {
            throw BackupOperationError.cloudOperationFailed(.containerNotFound)
        }

        // Create timestamped filename
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let timestamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-") // Make filesystem-safe
        let filename = "CloudBackup-\(timestamp).\(BackupFile.fileExtension)"
        let destinationURL = cloudDir.appendingPathComponent(filename)

        do {
            _ = try await backupService.exportBackup(
                modelContext: modelContext,
                to: destinationURL,
                password: password,
                progress: progress
            )

            // Trigger iCloud upload
            try fileManager.startDownloadingUbiquitousItem(at: destinationURL)

            return destinationURL
        } catch {
            throw BackupOperationError.cloudOperationFailed(.uploadFailed(underlying: error))
        }
    }

    /// Deletes a backup from iCloud Drive
    /// - Parameter backup: The backup to delete
    public func deleteCloudBackup(_ backup: CloudBackupInfo) throws {
        guard fileManager.fileExists(atPath: backup.fileURL.path) else {
            throw BackupOperationError.importFailed(.fileNotFound(url: backup.fileURL))
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
                do {
                    try deleteCloudBackup(backup)
                } catch {
                    let desc = error.localizedDescription
                    Self.logger.warning("Failed to delete backup during retention: \(desc, privacy: .public)")
                }
            }
        }
    }

    /// Copies a local backup to iCloud Drive
    /// - Parameter localURL: The local backup file URL
    /// - Returns: The iCloud URL of the copied file
    public func copyToCloud(_ localURL: URL) throws -> URL {
        guard isICloudAvailable else {
            throw BackupOperationError.cloudOperationFailed(.iCloudNotAvailable)
        }

        try ensureCloudBackupDirectoryExists()

        guard let cloudDir = cloudBackupDirectory else {
            throw BackupOperationError.cloudOperationFailed(.containerNotFound)
        }

        let destinationURL = cloudDir.appendingPathComponent(localURL.lastPathComponent)

        // Remove existing file if present
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: localURL, to: destinationURL)

        return destinationURL
    }

    // MARK: - Private Helpers

    func updateScheduledBackups() {
        if let modelContext = scheduledModelContext {
            startScheduledBackups(modelContext: modelContext)
        }
    }

    // MARK: - Initialization

    public init(backupService: BackupService) {
        self.backupService = backupService

        // Load last cloud backup date
        let timestamp = UserDefaults.standard.double(forKey: Keys.lastCloudBackupDate)
        if timestamp > 0 {
            lastCloudBackupDate = Date(timeIntervalSinceReferenceDate: timestamp)
        }
    }

    deinit {
        // Ensure scheduled backup task is cancelled when service is deallocated
        // We can't access MainActor-isolated properties from deinit, but Task cleanup
        // will happen automatically when this object is deallocated
        // The task holds a weak reference to self, so it will stop naturally
    }
}
// swiftlint:enable type_body_length
