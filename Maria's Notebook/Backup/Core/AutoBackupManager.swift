import Foundation
import SwiftData
import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#endif

/// Manages automatic backups including:
/// - Backups on app quit
/// - Scheduled interval backups while app is running
/// - Pre-destructive operation backups
@Observable
@MainActor
final class AutoBackupManager {
    private static let logger = Logger.backup

    // MARK: - Settings

    @ObservationIgnored
    @AppStorage(UserDefaultsKeys.autoBackupEnabled) private var isEnabled = true
    @ObservationIgnored
    @AppStorage(UserDefaultsKeys.autoBackupRetentionCount) private var retentionCount = 10
    @ObservationIgnored
    @AppStorage(UserDefaultsKeys.autoBackupScheduledEnabled) private var scheduledEnabled = false
    @ObservationIgnored
    @AppStorage(UserDefaultsKeys.autoBackupIntervalHours) private var intervalHours = 4

    // MARK: - State

    private(set) var lastScheduledBackupDate: Date?
    private(set) var isPerformingBackup = false
    private(set) var lastBackupResult: BackupResult?
    
    /// Modern event-based notification - SwiftUI views can observe this
    private(set) var lastBackupEvent: BackupEvent?

    // MARK: - Types
    
    /// Modern event-based notification system replacing NotificationCenter
    struct BackupEvent: Sendable {
        let trigger: BackupTrigger
        let result: BackupEventResult
        let timestamp: Date
        
        enum BackupEventResult: Sendable {
            case success(URL)
            case failure(Error)
        }
    }

    enum BackupResult {
        case success(Date, URL)
        case failure(Date, Error)

        var date: Date {
            switch self {
            case .success(let date, _): return date
            case .failure(let date, _): return date
            }
        }

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
    }

    enum BackupTrigger: String, Sendable {
        case appQuit = "AppQuit"
        case scheduled = "Scheduled"
        case preDestructive = "PreDestructive"
        case manual = "Manual"
    }

    // MARK: - Properties

    private let backupService: BackupService
    private var scheduledBackupTask: Task<Void, Never>?
    private var modelContext: ModelContext?

    // MARK: - Initialization

    init(backupService: BackupService) {
        self.backupService = backupService
        
        // Load last scheduled backup date from UserDefaults
        let timestamp = UserDefaults.standard.double(forKey: "AutoBackup.lastScheduledDate")
        if timestamp > 0 {
            lastScheduledBackupDate = Date(timeIntervalSinceReferenceDate: timestamp)
        }
    }

    // MARK: - Scheduled Backup Management

    /// Starts the scheduled backup timer
    /// - Parameter modelContext: The SwiftData model context to use for backups
    func startScheduledBackups(modelContext: ModelContext) {
        self.modelContext = modelContext
        stopScheduledBackups()

        guard scheduledEnabled && intervalHours > 0 else { return }

        scheduledBackupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { break }

                // Calculate time until next backup
                let intervalSeconds = TimeInterval(self.intervalHours * 3600)
                let nextBackupTime: Date

                if let lastBackup = self.lastScheduledBackupDate {
                    nextBackupTime = lastBackup.addingTimeInterval(intervalSeconds)
                } else {
                    // First backup after interval from now
                    nextBackupTime = Date().addingTimeInterval(intervalSeconds)
                }

                let waitTime = max(0, nextBackupTime.timeIntervalSinceNow)

                // Wait until next backup time
                if waitTime > 0 {
                    do {
                        try await Task.sleep(for: .seconds(waitTime))
                    } catch {
                        Self.logger.warning("Task sleep interrupted: \(error)")
                        break
                    }
                }

                // Check if still enabled and not cancelled
                guard !Task.isCancelled, self.scheduledEnabled else { break }

                // Perform scheduled backup
                await self.performScheduledBackup()
            }
        }
    }

    /// Stops the scheduled backup timer
    func stopScheduledBackups() {
        scheduledBackupTask?.cancel()
        scheduledBackupTask = nil
    }

    /// Performs a scheduled backup
    private func performScheduledBackup() async {
        guard let modelContext = modelContext else { return }
        _ = await performBackup(modelContext: modelContext, trigger: .scheduled, prefix: "ScheduledBackup")
    }

    // MARK: - App Quit Backup

    /// Performs an automatic backup when the app quits.
    /// This runs on the main thread (acceptable since app is closing).
    func performBackupOnQuit(modelContext: ModelContext) async {
        guard isEnabled else { return }
        _ = await performBackup(modelContext: modelContext, trigger: .appQuit, prefix: "AutoBackup")
    }

    // MARK: - Pre-Destructive Backup

    /// Creates a backup before a potentially destructive operation
    /// - Parameters:
    ///   - modelContext: The SwiftData model context
    ///   - operationName: Name of the operation (for filename)
    /// - Returns: URL of the created backup, or nil if backup failed
    func createPreDestructiveBackup(
        modelContext: ModelContext,
        operationName: String
    ) async -> URL? {
        let sanitizedName = operationName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")

        let result = await performBackup(
            modelContext: modelContext,
            trigger: .preDestructive,
            prefix: "PreOp-\(sanitizedName)"
        )

        if case .success(_, let url) = result {
            return url
        }
        return nil
    }

    // MARK: - Core Backup Logic

    private func performBackup(
        modelContext: ModelContext,
        trigger: BackupTrigger,
        prefix: String
    ) async -> BackupResult {
        guard !isPerformingBackup else {
            let result = BackupResult.failure(Date(), NSError(
                domain: "AutoBackupManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Backup already in progress"]
            ))
            return result
        }

        isPerformingBackup = true
        defer { isPerformingBackup = false }

        let backupDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto")

        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        } catch {
            Self.logger.warning("Failed to create backup directory: \(error)")
        }

        // Create timestamped filename
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let timestamp = formatter.string(from: Date())
        let filename = "\(prefix)-\(timestamp).\(BackupFile.fileExtension)"
        let url = backupDir.appendingPathComponent(filename)

        // Perform export
        do {
            _ = try await backupService.exportBackup(modelContext: modelContext, to: url) { _, _ in
                // Silent progress
            }

            // Update tracking
            if trigger == .scheduled {
                lastScheduledBackupDate = Date()
                UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: "AutoBackup.lastScheduledDate")
            }

            // Cleanup old backups (Retention Policy)
            cleanupOldBackups(in: backupDir, keeping: retentionCount)

            let result = BackupResult.success(Date(), url)
            lastBackupResult = result

            // Publish event using modern Observation pattern
            lastBackupEvent = BackupEvent(
                trigger: trigger,
                result: .success(url),
                timestamp: Date()
            )

            return result
        } catch {
            Self.logger.debug("Backup failed (\(trigger.rawValue)): \(error.localizedDescription)")

            let result = BackupResult.failure(Date(), error)
            lastBackupResult = result

            // Publish event using modern Observation pattern
            lastBackupEvent = BackupEvent(
                trigger: trigger,
                result: .failure(error),
                timestamp: Date()
            )

            return result
        }
    }

    private func cleanupOldBackups(in dir: URL, keeping count: Int) {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: [.creationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            Self.logger.warning("Failed to list directory contents: \(error)")
            return
        }

        // Filter to auto-backup files only (matches AutoBackup-, ScheduledBackup-, PreOp-)
        let autoBackups = files.filter { url in
            let name = url.lastPathComponent
            return name.hasPrefix("AutoBackup-") ||
                   name.hasPrefix("ScheduledBackup-") ||
                   name.hasPrefix("PreOp-")
        }

        // Sort by creation date (oldest first)
        let sorted = autoBackups.sorted { url1, url2 in
            let date1: Date
            do {
                date1 = try url1.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
            } catch {
                Self.logger.warning("Failed to get creation date for \(url1.lastPathComponent): \(error)")
                date1 = Date.distantPast
            }
            
            let date2: Date
            do {
                date2 = try url2.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date.distantPast
            } catch {
                Self.logger.warning("Failed to get creation date for \(url2.lastPathComponent): \(error)")
                date2 = Date.distantPast
            }
            
            return date1 < date2
        }

        // Delete oldest if we exceed retention count
        if sorted.count > count {
            let toDelete = sorted.prefix(sorted.count - count)
            for url in toDelete {
                do {
                    try FileManager.default.removeItem(at: url)
                } catch {
                    Self.logger.warning("Failed to delete old backup \(url.lastPathComponent): \(error)")
                }
            }
        }
    }

    // MARK: - Settings Access

    var enabled: Bool {
        get { isEnabled }
        set { isEnabled = newValue }
    }

    var retention: Int {
        get { retentionCount }
        set { retentionCount = max(1, min(newValue, 100)) }
    }

    var isScheduledBackupEnabled: Bool {
        get { scheduledEnabled }
        set {
            scheduledEnabled = newValue
            if newValue, let context = modelContext {
                startScheduledBackups(modelContext: context)
            } else {
                stopScheduledBackups()
            }
        }
    }

    var backupIntervalHours: Int {
        get { intervalHours }
        set {
            intervalHours = max(1, min(newValue, 24))
            // Restart scheduled backups with new interval
            if scheduledEnabled, let context = modelContext {
                startScheduledBackups(modelContext: context)
            }
        }
    }

    /// Time until next scheduled backup
    var timeUntilNextBackup: TimeInterval? {
        guard scheduledEnabled else { return nil }
        let intervalSeconds = TimeInterval(intervalHours * 3600)

        if let lastBackup = lastScheduledBackupDate {
            let nextBackup = lastBackup.addingTimeInterval(intervalSeconds)
            return max(0, nextBackup.timeIntervalSinceNow)
        }
        return intervalSeconds
    }
}

