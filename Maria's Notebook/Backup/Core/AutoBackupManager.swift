import Foundation
import CoreData
import SwiftUI
import OSLog
#if os(macOS)
import AppKit
#endif

/// Manages automatic backups including:
/// - Backups on app quit
/// - Scheduled interval backups while app is running
/// - Background (iOS scene-phase / BGProcessingTask) backups
/// - Pre-destructive operation backups
@Observable
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
    enum BackupEventResult: Sendable {
        case success(URL)
        case failure(Error)
    }

    struct BackupEvent: Sendable {
        let trigger: BackupTrigger
        let result: BackupEventResult
        let timestamp: Date
    }

    enum BackupResult {
        case success(Date, URL)
        case failure(Date, Error)
        /// No persistent-history transactions since the last auto-backup —
        /// nothing new to protect, so no file was written.
        case skippedNoChanges(Date)

        var date: Date {
            switch self {
            case .success(let date, _): return date
            case .failure(let date, _): return date
            case .skippedNoChanges(let date): return date
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
        case background = "Background"
    }

    // MARK: - Properties

    private let coordinator: BackupCoordinator
    private let changeTracker = BackupChangeTracker()
    private var scheduledBackupTask: Task<Void, Never>?
    private var viewContext: NSManagedObjectContext?

    // MARK: - Initialization

    init(
        coordinator: BackupCoordinator
    ) {
        self.coordinator = coordinator

        // Load last scheduled backup date from UserDefaults
        let timestamp = UserDefaults.standard.double(forKey: "AutoBackup.lastScheduledDate")
        if timestamp > 0 {
            lastScheduledBackupDate = Date(timeIntervalSinceReferenceDate: timestamp)
        }
    }

    // MARK: - Scheduled Backup Management

    /// Starts the scheduled backup timer
    /// - Parameter viewContext: The SwiftData model context to use for backups
    func startScheduledBackups(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        stopScheduledBackups()

        guard scheduledEnabled && intervalHours > 0 else { return }

        scheduledBackupTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }

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
        guard let viewContext else { return }
        _ = await performBackup(viewContext: viewContext, trigger: .scheduled, prefix: "ScheduledBackup")
        // Advance the schedule clock regardless of outcome (success, skip, or
        // failure). A failed attempt must still move `lastScheduledBackupDate`
        // forward, otherwise the timer loop computes a zero wait and retries
        // the full payload collection in a hot loop until the app quits.
        markScheduledBackupPerformed()
    }

    // MARK: - App Quit Backup

    /// Performs an automatic backup when the app quits.
    /// This runs on the main thread (acceptable since app is closing).
    func performBackupOnQuit(viewContext: NSManagedObjectContext) async {
        guard isEnabled else { return }
        _ = await performBackup(viewContext: viewContext, trigger: .appQuit, prefix: "AutoBackup")
    }

    // MARK: - Background Backup (iOS scene phase + BGProcessingTask)

    /// Automatic backup when the app moves to the background (iOS/iPadOS) or
    /// a background processing task fires. Change-gated like every other
    /// automatic trigger, so an untouched dataset costs nothing.
    func performBackgroundBackup(viewContext: NSManagedObjectContext) async {
        guard isEnabled else { return }
        _ = await performBackup(viewContext: viewContext, trigger: .background, prefix: "AutoBackup")
    }

    // MARK: - Core Backup Logic

    private func performBackup(
        viewContext: NSManagedObjectContext,
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

        // Skip automatic backups when persistent history shows no transactions
        // since the last one — nothing new to protect. Manual and
        // pre-destructive backups always run. (The schedule clock advances in
        // performScheduledBackup, after every scheduled attempt.)
        let automaticTriggers: Set<BackupTrigger> = [.appQuit, .scheduled, .background]
        if automaticTriggers.contains(trigger),
           !changeTracker.hasChangesSinceLastBackup(in: viewContext) {
            Self.logger.info(
                "Auto-backup (\(trigger.rawValue, privacy: .public)) skipped \u{2014} no changes since last backup"
            )
            return .skippedNoChanges(Date())
        }

        // Resolve auto-backup directory.
        // 1) If the user picked a default folder (Settings > Backup > Storage), put auto-backups
        //    in an `Auto/` subdirectory of that folder so iCloud Drive / Files-app users see them.
        // 2) Otherwise fall back to `Documents/Backups/Auto`.
        let (backupDir, securityScopedRoot) = resolveAutoBackupDirectory()
        if let root = securityScopedRoot, root.startAccessingSecurityScopedResource() {
            defer { root.stopAccessingSecurityScopedResource() }
            return await runExport(in: backupDir, trigger: trigger, prefix: prefix, viewContext: viewContext)
        }
        return await runExport(in: backupDir, trigger: trigger, prefix: prefix, viewContext: viewContext)
    }

    /// Returns the directory auto-backups should be written into, plus the security-scoped
    /// root URL that must be accessed (when the destination is a user-bookmarked folder).
    private func resolveAutoBackupDirectory() -> (URL, securityScopedRoot: URL?) {
        if let userFolder = BackupDestination.resolveDefaultFolder() {
            let auto = userFolder.appendingPathComponent("Auto", isDirectory: true)
            let needsScope = BackupDestination.resolveBookmarkedFolder() != nil
            return (auto, needsScope ? userFolder : nil)
        }
        let fallback = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto", isDirectory: true)
        return (fallback, nil)
    }

    private func runExport(
        in backupDir: URL,
        trigger: BackupTrigger,
        prefix: String,
        viewContext: NSManagedObjectContext
    ) async -> BackupResult {
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

        do {
            _ = try await coordinator.exportBackup(viewContext: viewContext, to: url) { _, _ in
                // Silent progress
            }

            // New change-detection baseline: the data just backed up.
            changeTracker.recordBackupPoint(context: viewContext)

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
            // A failed auto-backup is a data-protection gap, not a debug detail.
            Self.logger.error(
                "Backup failed (\(trigger.rawValue, privacy: .public)): \(error.localizedDescription, privacy: .public)"
            )

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

    private func markScheduledBackupPerformed() {
        lastScheduledBackupDate = Date()
        UserDefaults.standard.set(
            Date().timeIntervalSinceReferenceDate,
            forKey: "AutoBackup.lastScheduledDate"
        )
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
            if newValue, let context = viewContext {
                startScheduledBackups(viewContext: context)
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
            if scheduledEnabled, let context = viewContext {
                startScheduledBackups(viewContext: context)
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
