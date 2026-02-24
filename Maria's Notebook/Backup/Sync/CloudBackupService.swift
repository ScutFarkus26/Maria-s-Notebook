// CloudBackupService.swift
// Handles iCloud Drive integration for backups

import Foundation
import SwiftData
import OSLog

/// Service for managing backups in iCloud Drive
/// Provides automatic cloud sync for backup files without requiring manual file management
@Observable
@MainActor
public final class CloudBackupService {

    // MARK: - Types
    
    /// Modern event-based notification for cloud backup operations
    public struct CloudBackupEvent: Sendable {
        public let timestamp: Date
        public let result: CloudBackupEventResult
        
        public enum CloudBackupEventResult: Sendable {
            case completed(URL)
            case failed(Error)
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

    /// Configuration for retry logic
    public struct RetryConfiguration: Sendable {
        public var maxRetries: Int
        public var baseDelaySeconds: Double
        public var maxDelaySeconds: Double
        public var backoffMultiplier: Double

        public static let `default` = RetryConfiguration(
            maxRetries: 3,
            baseDelaySeconds: 1.0,
            maxDelaySeconds: 30.0,
            backoffMultiplier: 2.0
        )

        public init(maxRetries: Int, baseDelaySeconds: Double, maxDelaySeconds: Double, backoffMultiplier: Double) {
            self.maxRetries = maxRetries
            self.baseDelaySeconds = baseDelaySeconds
            self.maxDelaySeconds = maxDelaySeconds
            self.backoffMultiplier = backoffMultiplier
        }
    }

    /// Configuration for scheduled cloud backups
    public struct ScheduleConfiguration: Codable, Sendable {
        public var enabled: Bool
        public var intervalHours: Int
        public var retentionCount: Int

        public static let `default` = ScheduleConfiguration(
            enabled: false,
            intervalHours: 24,
            retentionCount: 7
        )

        public init(enabled: Bool, intervalHours: Int, retentionCount: Int) {
            self.enabled = enabled
            self.intervalHours = intervalHours
            self.retentionCount = retentionCount
        }
    }

    // MARK: - Observable State

    public private(set) var isPerformingBackup = false
    public private(set) var lastCloudBackupDate: Date?
    public private(set) var nextScheduledBackupDate: Date?
    public private(set) var currentRetryAttempt: Int = 0
    
    /// Modern event stream - SwiftUI views can observe this
    public private(set) var lastBackupEvent: CloudBackupEvent?

    // MARK: - Properties

    private let backupService: BackupService
    private let fileManager = FileManager.default

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
                    print("⚠️ [Backup:\(#function)] Failed to decode schedule configuration: \(error)")
                }
            }
            return .default
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                UserDefaults.standard.set(data, forKey: "CloudBackup.scheduleConfig")
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to encode schedule configuration: \(error)")
            }
            updateScheduledBackups()
        }
    }

    /// Scheduled backup task
    private var scheduledBackupTask: Task<Void, Never>?

    /// Model context for scheduled backups
    private var modelContext: ModelContext?

    // MARK: - UserDefaults Keys

    private enum Keys {
        static let lastCloudBackupDate = "CloudBackup.lastBackupDate"
        static let scheduleConfig = "CloudBackup.scheduleConfig"
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

    /// Lists all backups available in iCloud Drive
    /// - Returns: Array of cloud backup info sorted by date (newest first)
    public func listCloudBackups() async throws -> [CloudBackupInfo] {
        guard isICloudAvailable else {
            throw BackupOperationError.cloudOperationFailed(.iCloudNotAvailable)
        }

        guard let cloudDir = cloudBackupDirectory else {
            throw BackupOperationError.cloudOperationFailed(.containerNotFound)
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

        let enumerator = fileManager.enumerator(
            at: cloudDir,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )
        guard let enumerator = enumerator else {
            return []
        }

        var backups: [CloudBackupInfo] = []

        // Collect URLs first to avoid makeIterator() in async context (Swift 6 requirement)
        let fileURLs = enumerator.allObjects.compactMap { $0 as? URL }

        for fileURL in fileURLs {
            guard fileURL.pathExtension == BackupFile.fileExtension else { continue }

            let resourceValues: URLResourceValues
            do {
                resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
            } catch {
                print("⚠️ [Backup:\(#function)] Failed to get resource values for \(fileURL.lastPathComponent): \(error)")
                continue
            }

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
        }

        // Sort by modification date (newest first)
        return backups.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    /// Downloads a backup from iCloud if not already downloaded
    /// - Parameter backup: The backup to download
    /// - Returns: The local URL once downloaded
    public func downloadBackupIfNeeded(_ backup: CloudBackupInfo) async throws -> URL {
        guard isICloudAvailable else {
            throw BackupOperationError.cloudOperationFailed(.iCloudNotAvailable)
        }

        if backup.isDownloaded {
            return backup.fileURL
        }

        // Start download
        try fileManager.startDownloadingUbiquitousItem(at: backup.fileURL)

        // Use NSFileCoordinator to wait for the file to be available
        // Modernized using structured concurrency with timeout support
        return try await withThrowingTaskGroup(of: URL.self) { group in
            // Add the file coordination task
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                    // NSFileCoordinator still requires blocking, so run on cooperative thread pool
                    Task.detached(priority: .userInitiated) {
                        let coordinator = NSFileCoordinator()
                        var coordinatorError: NSError?
                        
                        // Use actor for thread-safe single resumption
                        actor ResumeTracker {
                            var hasResumed = false
                            
                            func tryResume(with result: Result<URL, Error>) -> Bool {
                                guard !hasResumed else { return false }
                                hasResumed = true
                                return true
                            }
                        }
                        
                        let tracker = ResumeTracker()
                        
                        coordinator.coordinate(
                            readingItemAt: backup.fileURL,
                            options: [.withoutChanges],
                            error: &coordinatorError
                        ) { url in
                            Task {
                                // Check download status one final time
                                do {
                                    let resourceValues = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                                    if resourceValues.ubiquitousItemDownloadingStatus == .current || 
                                       resourceValues.ubiquitousItemDownloadingStatus == nil {
                                        if await tracker.tryResume(with: .success(url)) {
                                            continuation.resume(returning: url)
                                        }
                                    } else {
                                        let error = BackupOperationError.cloudOperationFailed(.downloadFailed(underlying: NSError(domain: "CloudBackup", code: 404, userInfo: [NSLocalizedDescriptionKey: "File '\(backup.fileName)' not downloaded"])))
                                        if await tracker.tryResume(with: .failure(error)) {
                                            continuation.resume(throwing: error)
                                        }
                                    }
                                } catch {
                                    let wrappedError = BackupOperationError.cloudOperationFailed(.downloadFailed(underlying: error))
                                    if await tracker.tryResume(with: .failure(wrappedError)) {
                                        continuation.resume(throwing: wrappedError)
                                    }
                                }
                            }
                        }
                        
                        // Handle coordination error
                        if let error = coordinatorError {
                            Task {
                                let wrappedError = BackupOperationError.cloudOperationFailed(.downloadFailed(underlying: error))
                                if await tracker.tryResume(with: .failure(wrappedError)) {
                                    continuation.resume(throwing: wrappedError)
                                }
                            }
                        }
                    }
                }
            }
            
            // Add timeout task using structured concurrency
            group.addTask {
                try await Task.sleep(for: .seconds(60))
                throw BackupOperationError.cloudOperationFailed(.downloadFailed(underlying: NSError(domain: "CloudBackup", code: 408, userInfo: [NSLocalizedDescriptionKey: "Download timed out for '\(backup.fileName)'"])))
            }
            
            // Return the first result (either success or timeout)
            guard let result = try await group.next() else {
                throw BackupOperationError.cloudOperationFailed(.downloadFailed(underlying: NSError(domain: "CloudBackup", code: 500, userInfo: [NSLocalizedDescriptionKey: "No task result available"])))
            }
            group.cancelAll() // Cancel the other task
            return result
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
                    print("⚠️ [Backup:\(#function)] Failed to delete backup during retention: \(error)")
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

    // MARK: - Retry Logic with Exponential Backoff

    /// Executes an operation with automatic retry and exponential backoff.
    ///
    /// - Parameters:
    ///   - operation: The async operation to perform
    ///   - shouldRetry: Closure to determine if error is retryable (default: true for all errors)
    /// - Returns: The result of the operation
    public func withRetry<T>(
        operation: @escaping () async throws -> T,
        shouldRetry: @escaping (Error) -> Bool = { _ in true }
    ) async throws -> T {
        var lastError: Error?
        var delay = retryConfiguration.baseDelaySeconds

        for attempt in 0...retryConfiguration.maxRetries {
            currentRetryAttempt = attempt

            do {
                let result = try await operation()
                currentRetryAttempt = 0
                return result
            } catch {
                lastError = error

                // Check if we should retry
                if attempt < retryConfiguration.maxRetries && shouldRetry(error) {
                    // Wait with exponential backoff
                    let jitter = Double.random(in: 0...0.5)
                    let actualDelay = min(delay + jitter, retryConfiguration.maxDelaySeconds)

                    Logger.backup.error("Attempt \(attempt + 1) failed: \(error.localizedDescription). Retrying in \(actualDelay)s...")

                    try await Task.sleep(for: .seconds(actualDelay))
                    delay *= retryConfiguration.backoffMultiplier
                } else {
                    break
                }
            }
        }

        currentRetryAttempt = 0
        throw BackupOperationError.cloudOperationFailed(.uploadFailed(underlying: lastError!))
    }

    /// Exports a backup to iCloud with automatic retry on failure.
    public func exportToCloudWithRetry(
        modelContext: ModelContext,
        password: String? = nil,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> URL {
        try await withRetry {
            try await self.exportToCloud(
                modelContext: modelContext,
                password: password,
                progress: progress
            )
        } shouldRetry: { error in
            // Use the error's shouldRetry property if available
            if let backupError = error as? BackupOperationError {
                return backupError.shouldRetry
            }
            return true
        }
    }

    // MARK: - Scheduled Cloud Backups

    /// Starts scheduled cloud backups.
    ///
    /// - Parameter modelContext: The SwiftData model context to use for backups
    public func startScheduledBackups(modelContext: ModelContext) {
        self.modelContext = modelContext
        stopScheduledBackups()

        guard scheduleConfiguration.enabled && scheduleConfiguration.intervalHours > 0 else {
            return
        }

        // Load last backup date
        let timestamp = UserDefaults.standard.double(forKey: Keys.lastCloudBackupDate)
        if timestamp > 0 {
            lastCloudBackupDate = Date(timeIntervalSinceReferenceDate: timestamp)
        }

        scheduledBackupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                // Calculate time until next backup
                let intervalSeconds = TimeInterval(self.scheduleConfiguration.intervalHours * 3600)
                let nextBackupTime: Date

                if let lastBackup = self.lastCloudBackupDate {
                    nextBackupTime = lastBackup.addingTimeInterval(intervalSeconds)
                } else {
                    // First backup after interval from now
                    nextBackupTime = Date().addingTimeInterval(intervalSeconds)
                }

                self.nextScheduledBackupDate = nextBackupTime

                let waitTime = max(0, nextBackupTime.timeIntervalSinceNow)

                // Wait until next backup time
                if waitTime > 0 {
                    do {
                        try await Task.sleep(for: .seconds(waitTime))
                    } catch {
                        print("⚠️ [Backup:\(#function)] Task sleep interrupted: \(error)")
                    }
                }

                // Check if still enabled and not cancelled
                guard !Task.isCancelled, self.scheduleConfiguration.enabled else { break }

                // Perform scheduled backup
                await self.performScheduledCloudBackup()
            }
        }
    }

    /// Stops scheduled cloud backups.
    public func stopScheduledBackups() {
        scheduledBackupTask?.cancel()
        scheduledBackupTask = nil
        nextScheduledBackupDate = nil
    }

    /// Performs a scheduled cloud backup.
    private func performScheduledCloudBackup() async {
        guard let modelContext = modelContext else { return }
        guard !isPerformingBackup else { return }

        isPerformingBackup = true
        defer { isPerformingBackup = false }

        do {
            let backupURL = try await exportToCloudWithRetry(
                modelContext: modelContext,
                password: nil,
                progress: { _, _ in }
            )

            // Update last backup date
            lastCloudBackupDate = Date()
            UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: Keys.lastCloudBackupDate)

            // Apply retention policy
            try await applyRetentionPolicy(maxCount: scheduleConfiguration.retentionCount)

            // Publish event using modern Observation pattern
            lastBackupEvent = CloudBackupEvent(
                timestamp: Date(),
                result: .completed(backupURL)
            )

        } catch {
            Logger.backup.error("Scheduled backup failed: \(error.localizedDescription)")

            // Publish event using modern Observation pattern
            lastBackupEvent = CloudBackupEvent(
                timestamp: Date(),
                result: .failed(error)
            )
        }
    }

    private func updateScheduledBackups() {
        if let modelContext = modelContext {
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
import SwiftData
