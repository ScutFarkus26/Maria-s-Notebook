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
        /// last auto-backup (nothing new to protect).
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
    private let changeTracker: BackupChangeTracker
    /// Where this device keeps the name of its own folder in `Auto/`
    /// (`AutoBackupFolders.deviceFolderName`), and how its automatic backups
    /// have gone (`automaticBackupFailingSince`, `lastBackupOnThisDevice`).
    private let deviceDefaults: UserDefaults
    /// Whether the first download from iCloud is still under way
    /// (`FirstDownloadGate`); a stand-in for tests.
    private let firstDownloadPending: @Sendable () -> Bool
    /// Where it marks that name as its own (the Keychain; for tests, a stand-in).
    private let deviceMark: AutoBackupFolders.DeviceMark
    /// The `Auto/` folder to write into instead of the backup folder's: for
    /// tests, which must never write into the real one. Nil in the app.
    private let autoFolderOverride: URL?
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
        coordinator: BackupCoordinator,
        deviceDefaults: UserDefaults = .standard,
        deviceMark: AutoBackupFolders.DeviceMark = .keychain,
        autoFolder: URL? = nil,
        changeTracker: BackupChangeTracker = BackupChangeTracker(),
        firstDownloadPending: @escaping @Sendable () -> Bool = { FirstDownloadGate.isPending() }
    ) {
        self.coordinator = coordinator
        self.deviceDefaults = deviceDefaults
        self.deviceMark = deviceMark
        self.autoFolderOverride = autoFolder
        self.changeTracker = changeTracker
        self.firstDownloadPending = firstDownloadPending
        noteExportCutShort()

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

        // During a first download the notebook may be half there: the backup
        // is still written, for what this device holds, but as a partial one
        // that is never counted among the complete ones (#14).
        let partial = firstDownloadPending()
        if partial {
            Self.logger.info(
                "Backup (\(trigger.rawValue, privacy: .public)) written as partial \u{2014} first download not finished"
            )
        }
        let prefix = Self.fileNamePrefix(prefix, firstDownloadPending: partial)

        // Resolve auto-backup directory.
        // 1) If the user picked a default folder (Settings > Backup > Storage), put auto-backups
        //    in an `Auto/` subdirectory of that folder so iCloud Drive / Files-app users see them.
        // 2) Otherwise fall back to `Documents/Backups/Auto`.
        // Inside it, this device writes to a folder of its own (`AutoBackupFolders`).
        let (autoFolder, securityScopedRoot) = resolveAutoBackupDirectory()
        if let root = securityScopedRoot, root.startAccessingSecurityScopedResource() {
            defer { root.stopAccessingSecurityScopedResource() }
            return await runExport(
                in: autoFolder, trigger: trigger, prefix: prefix,
                viewContext: viewContext, stopsWhenCancelled: stopsWhenCancelled
            )
        }
        return await runExport(
            in: autoFolder, trigger: trigger, prefix: prefix,
            viewContext: viewContext, stopsWhenCancelled: stopsWhenCancelled
        )
    }

    /// Returns the `Auto/` directory auto-backups go in (each device in its own folder
    /// inside it), plus the security-scoped root URL that must be accessed (when the
    /// destination is a user-bookmarked folder).
    private func resolveAutoBackupDirectory() -> (URL, securityScopedRoot: URL?) {
        if let autoFolderOverride { return (autoFolderOverride, nil) }
        if let userFolder = BackupDestination.resolveDefaultFolder() {
            let auto = userFolder.appendingPathComponent(AutoBackupFolders.autoFolderName, isDirectory: true)
            let needsScope = BackupDestination.resolveBookmarkedFolder() != nil
            return (auto, needsScope ? userFolder : nil)
        }
        let fallback = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Backups/Auto", isDirectory: true)
        return (fallback, nil)
    }

    /// This device's own folder inside `autoFolder`.
    private func deviceFolder(in autoFolder: URL) -> URL {
        let name = AutoBackupFolders.deviceFolderName(
            defaults: deviceDefaults,
            kind: AutoBackupFolders.currentDeviceKind(),
            mark: deviceMark
        )
        return AutoBackupFolders.deviceFolder(in: autoFolder, named: name)
    }

    private func runExport(
        in autoFolder: URL,
        trigger: BackupTrigger,
        prefix: String,
        viewContext: NSManagedObjectContext,
        stopsWhenCancelled: Bool
    ) async -> BackupResult {
        let backupDir = deviceFolder(in: autoFolder)
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

        // Cleared however the export ends; found at the next launch, it means
        // the process was ended mid-write (`noteExportCutShort`).
        let automatic = Self.automaticTriggers.contains(trigger)
        if automatic { deviceDefaults.set(Date().timeIntervalSinceReferenceDate, forKey: Self.inFlightKey) }
        defer { if automatic { deviceDefaults.removeObject(forKey: Self.inFlightKey) } }

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

            // Retention: this device's own folder, and the files older builds
            // left at the top of `Auto/`; never another device's folder.
            AutoBackupFolders.trimAfterBackup(autoFolder: autoFolder, deviceFolder: backupDir, keeping: retentionCount)

            let result = BackupResult.success(Date(), url)
            lastBackupResult = result
            recordWritten(at: Date(), partial: AutoBackupFolders.isPartial(filename))

            // Publish event using modern Observation pattern
            lastBackupEvent = BackupEvent(
                trigger: trigger,
                result: .success(url),
                timestamp: Date()
            )

            return result
        } catch {
            return exportFailed(error, trigger: trigger)
        }
    }

    /// Logs and publishes a failed export, and for an automatic one notes
    /// that this device's backups are failing (`automaticBackupFailingSince`).
    private func exportFailed(_ error: Error, trigger: BackupTrigger) -> BackupResult {
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
        if Self.automaticTriggers.contains(trigger), Self.countsAsFailure(error) { recordFailure(at: Date()) }

        // Publish event using modern Observation pattern
        lastBackupEvent = BackupEvent(
            trigger: trigger,
            result: .failure(error),
            timestamp: Date()
        )

        return result
    }

    private func markScheduledBackupPerformed() {
        lastScheduledBackupDate = Date()
        UserDefaults.standard.set(
            Date().timeIntervalSinceReferenceDate,
            forKey: UserDefaultsKeys.autoBackupLastScheduledDate
        )
    }

    // MARK: - Settings Access

    var enabled: Bool {
        get { isEnabled }
        set { isEnabled = newValue }
    }

}

extension AutoBackupManager {
    // MARK: - Automatic Triggers

    /// The backups made without being asked for: change-gated, and the ones
    /// whose failures `SettingsAttention` hears about.
    nonisolated static let automaticTriggers: Set<BackupTrigger> = [.appQuit, .scheduled, .background]

    /// The start of a backup's file name. While the private store is still
    /// downloading from iCloud for the first time (`FirstDownloadGate`), a
    /// backup is of a notebook that may be half there: it is written as a
    /// partial one (`AutoBackupFolders.partialPrefix`), which trimming never
    /// counts against the complete ones and "Restore last automatic backup"
    /// never offers.
    ///
    /// Until 2026-11 automatic backups were held back instead, but only for a
    /// day after the download began; one stuck for longer (days of school
    /// Wi-Fi) then wrote half-filled backups under the usual names, which
    /// pushed out the complete ones, and manual backups were never held
    /// (bug hunt 2026-11-02 #14). A partial backup still keeps what this
    /// device holds, its own unsent work included, however long the download takes.
    nonisolated static func fileNamePrefix(_ prefix: String, firstDownloadPending: Bool) -> String {
        firstDownloadPending ? AutoBackupFolders.partialPrefix + prefix : prefix
    }

    /// What Back Up Now and `create_backup` say of a backup made while the
    /// first download is under way.
    nonisolated static let firstDownloadWarning =
        "This device is still downloading your notebook from iCloud, so this backup may be missing some of it."

    // MARK: - How This Device's Backups Have Gone

    /// When this device's automatic backups started failing: the first
    /// failure since the last backup it wrote. In this device's own defaults
    /// only, like its folder's name. Settings' status rows show it
    /// (`SettingsAttention`): until 2026-11 nothing read a failed automatic
    /// backup, so a device whose every one failed only logged it, and
    /// another device's backups hid that it had none (#12).
    nonisolated static let failingSinceKey = "AutoBackup.failingSince"

    /// When this device last wrote a complete backup into its own folder.
    nonisolated static let lastWrittenKey = "AutoBackup.lastWrittenOnThisDevice"

    /// Set while an automatic export runs. Still set at launch, the process
    /// was ended mid-write (the Mac's quit limit, an iPad suspended while it
    /// backed up), so that backup failed though nothing said so.
    nonisolated static let inFlightKey = "AutoBackup.inFlightSince"

    /// When this device's automatic backups started failing, or nil while
    /// they work.
    var automaticBackupFailingSince: Date? {
        date(forKey: Self.failingSinceKey)
    }

    /// When this device last wrote a complete backup, automatic or by name,
    /// into its own folder; nil before the first since 2026-11.
    var lastBackupOnThisDevice: Date? {
        date(forKey: Self.lastWrittenKey)
    }

    /// Whether automatic backups run on this device at all: on leaving the
    /// app (quitting it on the Mac), or on a timer.
    var automaticBackupsOn: Bool {
        isEnabled || scheduledEnabled
    }

    /// A failure the guide should hear about. A run the system ended on
    /// purpose isn't one, and neither is a key iCloud Keychain hasn't brought
    /// yet during a first download, which sorts itself out.
    nonisolated static func countsAsFailure(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if case BackupEncryptionKeyStore.KeyStoreError.keyNotHereYet = error { return false }
        return true
    }

    /// A backup was written into this device's folder: the backups work.
    private func recordWritten(at date: Date, partial: Bool) {
        deviceDefaults.removeObject(forKey: Self.failingSinceKey)
        guard !partial else { return }
        deviceDefaults.set(date.timeIntervalSinceReferenceDate, forKey: Self.lastWrittenKey)
    }

    /// An automatic backup failed: the failing run starts now unless it
    /// already had.
    private func recordFailure(at date: Date) {
        guard deviceDefaults.object(forKey: Self.failingSinceKey) == nil else { return }
        deviceDefaults.set(date.timeIntervalSinceReferenceDate, forKey: Self.failingSinceKey)
    }

    /// At launch: an automatic export the last process never finished.
    private func noteExportCutShort() {
        guard let started = date(forKey: Self.inFlightKey) else { return }
        deviceDefaults.removeObject(forKey: Self.inFlightKey)
        Self.logger.error("The last automatic backup was cut short before it finished")
        recordFailure(at: started)
    }

    private func date(forKey key: String) -> Date? {
        guard deviceDefaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSinceReferenceDate: deviceDefaults.double(forKey: key))
    }

    // MARK: - Manual Backup

    /// A backup the guide asked for by name — from the MCP `create_backup`
    /// tool before a bulk change, for instance. Never change-gated and not
    /// subject to the auto-backup switch: an explicit request always writes
    /// a file, so the caller can rely on the path it gets back. During a
    /// first download it is a partial one (`fileNamePrefix`), and the
    /// receipt says so (`MCPNotebookTools.backupReceipt`).
    func performManualBackup(viewContext: NSManagedObjectContext) async -> BackupResult {
        await performBackup(viewContext: viewContext, trigger: .manual, prefix: "ManualBackup")
    }
}
