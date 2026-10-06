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
    /// A backup asked for while another is still being written.
    nonisolated struct AlreadyRunning: LocalizedError {
        var errorDescription: String? { "A backup is already running. It'll finish in a moment." }
    }

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
    /// When the last scene-phase/background-task backup ran (success or
    /// failure); the start of the gap in `performBackgroundBackup`.
    private(set) var lastBackgroundBackupDate: Date?
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
        /// No file was written: no persistent-history transactions since the
        /// last auto-backup (nothing new to protect), or the first download
        /// from iCloud is still under way (`waitsForFirstDownload`).
        case skippedNoChanges(Date)

    }

    enum BackupTrigger: String, Sendable {
        case appQuit = "AppQuit"
        case scheduled = "Scheduled"
        case manual = "Manual"
        case background = "Background"
    }

    // MARK: - Properties

    private let coordinator: BackupCoordinator
    private let changeTracker = BackupChangeTracker()
    #if os(macOS)
    /// The Mac's interval backup: one system-scheduled activity per backup.
    private let scheduledActivity = ScheduledBackupActivity()
    #else
    /// The interval loop (it only runs while the app is in the foreground).
    private var scheduledBackupTask: Task<Void, Never>?
    #endif
    private var viewContext: NSManagedObjectContext?

    // MARK: - Initialization

    init(
        coordinator: BackupCoordinator
    ) {
        self.coordinator = coordinator

        // Load last scheduled backup date from UserDefaults
        let timestamp = UserDefaults.standard.double(forKey: UserDefaultsKeys.autoBackupLastScheduledDate)
        if timestamp > 0 {
            lastScheduledBackupDate = Date(timeIntervalSinceReferenceDate: timestamp)
        }
        let backgroundTimestamp = UserDefaults.standard.double(forKey: UserDefaultsKeys.autoBackupLastBackgroundDate)
        if backgroundTimestamp > 0 {
            lastBackgroundBackupDate = Date(timeIntervalSinceReferenceDate: backgroundTimestamp)
        }
    }

    // MARK: - Scheduled Backup Management

    /// Starts (or restarts, from the current switch and interval) the
    /// interval backups, replacing any already scheduled. On the Mac the
    /// system runs each one (`ScheduledBackupActivity`); elsewhere a loop
    /// sleeps until it is due.
    /// - Parameter viewContext: The Core Data context to back up from
    func startScheduledBackups(viewContext: NSManagedObjectContext) {
        self.viewContext = viewContext
        stopScheduledBackups()

        guard scheduledEnabled && intervalHours > 0 else { return }

        #if os(macOS)
        armScheduledActivity()
        #else
        // Utility: automatic work the guide didn't ask for. The encode half
        // of the export inherits this priority off the main actor.
        scheduledBackupTask = Task(priority: .utility) { [weak self] in
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
        #endif
    }

    /// Stops the interval backups. A backup already running finishes.
    func stopScheduledBackups() {
        #if os(macOS)
        scheduledActivity.invalidate()
        #else
        scheduledBackupTask?.cancel()
        scheduledBackupTask = nil
        #endif
    }

    #if os(macOS)
    /// Arms the next interval backup, due when the loop would wake. Each run
    /// re-arms with the wait the loop would compute next: from the current
    /// interval, and none once the switch is off.
    private func armScheduledActivity() {
        guard let delay = nextScheduledBackupDelay() else { return }
        scheduledActivity.arm(after: delay) { [weak self] in
            // The loop's check after its sleep: switched off meanwhile?
            guard let self, self.scheduledEnabled else { return nil }
            await self.performScheduledBackup()
            return self.nextScheduledBackupDelay()
        }
    }

    private func nextScheduledBackupDelay() -> TimeInterval? {
        ScheduledBackupTiming.nextDelay(
            enabled: scheduledEnabled,
            intervalHours: intervalHours,
            lastBackup: lastScheduledBackupDate,
            now: Date()
        )
    }
    #endif

    /// Performs a scheduled backup.
    ///
    /// The interval backup is the one automatic trigger that can safely wait:
    /// a hot device or Low Power Mode skips it and the clock advances, so the
    /// next attempt comes one interval later. The quit, background, and
    /// pre-destructive backups are never deferred — those are the moments the
    /// data would otherwise be lost.
    func performScheduledBackup(policy: EnergyPolicy = .shared) async {
        guard let viewContext else { return }
        guard !policy.shouldDeferMaintenance else {
            Self.logger.notice(
                "Auto-backup (Scheduled) deferred one interval \u{2014} device hot or in Low Power Mode"
            )
            markScheduledBackupPerformed()
            return
        }
        _ = await performBackup(viewContext: viewContext, trigger: .scheduled, prefix: "ScheduledBackup")
        // Advance the schedule clock regardless of outcome (success, skip, or
        // failure). A failed attempt must still move `lastScheduledBackupDate`
        // forward, otherwise the next wait (the loop's sleep, or the Mac's
        // next activity) is zero and the full payload collection retries in
        // a hot loop until the app quits.
        markScheduledBackupPerformed()
    }

    // MARK: - App Quit Backup

    /// Performs an automatic backup when the app quits. Collection runs on
    /// the main actor; the encode/verify half runs off it (`BackupWriter`)
    /// at the quitting task's priority.
    func performBackupOnQuit(viewContext: NSManagedObjectContext) async {
        guard isEnabled else { return }
        _ = await performBackup(viewContext: viewContext, trigger: .appQuit, prefix: "AutoBackup")
    }

    // MARK: - Background Backup (iOS scene phase + BGProcessingTask)

    /// What a background-backup request did, so the BGProcessingTask can
    /// ask for an earlier retry when the device was too hot.
    enum BackgroundBackupOutcome: Equatable, Sendable {
        case ran
        case disabled
        /// Hot or Low Power Mode: nothing collected; try again later.
        case deferredConstrained
        /// A background backup ran less than the profile's gap ago.
        case tooSoon
    }

    /// Minimum time between two scene-phase background backups. Every app
    /// switch on the iPad used to export the whole store, and CloudKit
    /// imports keep the change gate open all day, so this was a full export
    /// per switch. On the charger routine protection can be frequent; on
    /// battery once an hour; hot or in Low Power Mode it waits (nil).
    nonisolated static func backgroundBackupMinimumGap(for profile: EnergyPolicy.Profile) -> TimeInterval? {
        switch profile {
        case .externalPower: return 15 * 60
        case .battery: return 60 * 60
        case .constrained: return nil
        }
    }

    /// Automatic backup when the app moves to the background (iOS/iPadOS) or
    /// a background processing task fires. Change-gated like every other
    /// automatic trigger, so an untouched dataset costs nothing; also skipped
    /// on a hot device or in Low Power Mode, and (for the scene-phase trigger,
    /// `enforcingMinimumGap`) within the profile's gap of the previous one.
    /// The quit and pre-destructive backups are never gated.
    /// `stopsWhenCancelled` is for the BGProcessingTask only: its export stops
    /// between record types once iPadOS ends the task, writing nothing.
    @discardableResult
    func performBackgroundBackup(
        viewContext: NSManagedObjectContext,
        enforcingMinimumGap: Bool = true,
        stopsWhenCancelled: Bool = false,
        policy: EnergyPolicy = .shared,
        now: Date = Date()
    ) async -> BackgroundBackupOutcome {
        guard isEnabled else { return .disabled }
        guard let gap = Self.backgroundBackupMinimumGap(for: policy.profile) else {
            Self.logger.notice("Auto-backup (Background) deferred \u{2014} device hot or in Low Power Mode")
            return .deferredConstrained
        }
        if enforcingMinimumGap, let last = lastBackgroundBackupDate, now.timeIntervalSince(last) < gap {
            Self.logger.info("Auto-backup (Background) skipped \u{2014} last one under \(Int(gap / 60)) min ago")
            return .tooSoon
        }
        let result = await performBackup(
            viewContext: viewContext,
            trigger: .background,
            prefix: "AutoBackup",
            stopsWhenCancelled: stopsWhenCancelled
        )
        if Self.startsBackgroundGap(result) {
            lastBackgroundBackupDate = now
            UserDefaults.standard.set(
                now.timeIntervalSinceReferenceDate,
                forKey: UserDefaultsKeys.autoBackupLastBackgroundDate
            )
        }
        return .ran
    }

    /// Whether a background backup's result starts the scene-phase gap. A
    /// written file does, and so does a failure, so a failing export is not
    /// retried in full on every app switch. Nothing to back up doesn't, and
    /// neither does a run iPadOS ended early: nothing was written, so the
    /// next app switch should try again.
    static func startsBackgroundGap(_ result: BackupResult) -> Bool {
        switch result {
        case .success:
            return true
        case .failure(_, let error):
            return !(error is CancellationError)
        case .skippedNoChanges:
            return false
        }
    }

    // MARK: - Core Backup Logic

    fileprivate func performBackup(
        viewContext: NSManagedObjectContext,
        trigger: BackupTrigger,
        prefix: String,
        stopsWhenCancelled: Bool = false
    ) async -> BackupResult {
        guard !isPerformingBackup else {
            Self.logger.info("Backup (\(trigger.rawValue, privacy: .public)) not started: one is already running")
            return .failure(Date(), AlreadyRunning())
        }

        isPerformingBackup = true
        defer { isPerformingBackup = false }

        if Self.waitsForFirstDownload(trigger) {
            Self.logger.info(
                "Auto-backup (\(trigger.rawValue, privacy: .public)) skipped \u{2014} first download not finished"
            )
            return .skippedNoChanges(Date())
        }
        // Skip automatic backups when persistent history shows no transactions
        // since the last one — nothing new to protect. Manual and
        // pre-destructive backups always run. (The schedule clock advances in
        // performScheduledBackup, after every scheduled attempt.)
        if Self.automaticTriggers.contains(trigger),
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
            return await runExport(
                in: backupDir, trigger: trigger, prefix: prefix,
                viewContext: viewContext, stopsWhenCancelled: stopsWhenCancelled
            )
        }
        return await runExport(
            in: backupDir, trigger: trigger, prefix: prefix,
            viewContext: viewContext, stopsWhenCancelled: stopsWhenCancelled
        )
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
        viewContext: NSManagedObjectContext,
        stopsWhenCancelled: Bool
    ) async -> BackupResult {
        // Ensure directory exists
        do {
            try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)
        } catch {
            Self.logger.warning("Failed to create backup directory: \(error)")
        }

        // Create timestamped filename
        let formatter = DateFormatters.iso8601DateTimeWithFractionalSeconds
        let timestamp = formatter.string(from: Date())
        let filename = "\(prefix)-\(timestamp).\(BackupFile.fileExtension)"
        let url = backupDir.appendingPathComponent(filename)

        // The change-detection baseline is what the stores held before the
        // rows were collected: a change saved during the write comes after it,
        // so the next automatic backup still sees it.
        let baseline = changeTracker.currentHistoryToken(context: viewContext)

        do {
            _ = try await coordinator.exportBackup(
                viewContext: viewContext,
                to: url,
                stopsWhenCancelled: stopsWhenCancelled
            ) { _, _ in
                // Silent progress
            }

            // New change-detection baseline: the data just backed up.
            changeTracker.recordBackupPoint(baseline)

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
            let triggerName = trigger.rawValue
            if error is CancellationError {
                // Only the BGProcessingTask's export stops when cancelled.
                Self.logger.notice(
                    "Auto-backup (\(triggerName, privacy: .public)) stopped \u{2014} the system ended the task"
                )
            } else {
                // A failed auto-backup is a data-protection gap, not a debug detail. The
                // error's own description, not its plain text: the case, type and cause.
                let reason = String(describing: error)
                Self.logger.error("Backup failed (\(triggerName, privacy: .public)): \(reason, privacy: .public)")
            }

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
            forKey: UserDefaultsKeys.autoBackupLastScheduledDate
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
                    // Coordinated: the folder is usually in iCloud Drive.
                    try UbiquitousFile.coordinatedDelete(url)
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

}

extension AutoBackupManager {
    // MARK: - Automatic Triggers

    /// The backups made without being asked for: change-gated, and held back
    /// during a first download.
    nonisolated static let automaticTriggers: Set<BackupTrigger> = [.appQuit, .scheduled, .background]

    /// Whether an automatic backup waits because the private store is still
    /// downloading from iCloud for the first time (`FirstDownloadGate`): a
    /// backup of a half-filled notebook counts toward the ones kept and can
    /// push out complete ones (2026-10-05 sync hunt). Manual and
    /// pre-destructive backups always run.
    nonisolated static func waitsForFirstDownload(
        _ trigger: BackupTrigger,
        firstDownloadPending: Bool = FirstDownloadGate.isPending()
            && FirstDownloadGate.armedRecently(within: 24 * 60 * 60)
    ) -> Bool {
        firstDownloadPending && automaticTriggers.contains(trigger)
    }

    // MARK: - Manual Backup

    /// A backup the guide asked for by name — from the MCP `create_backup`
    /// tool before a bulk change, for instance. Never change-gated and not
    /// subject to the auto-backup switch: an explicit request always writes
    /// a file, so the caller can rely on the path it gets back.
    func performManualBackup(viewContext: NSManagedObjectContext) async -> BackupResult {
        await performBackup(viewContext: viewContext, trigger: .manual, prefix: "ManualBackup")
    }
}
