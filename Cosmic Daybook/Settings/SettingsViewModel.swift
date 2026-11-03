import Foundation
import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

#if os(macOS)
import AppKit
#endif

/// What a finished backup or restore says in the banner above the backup
/// cards, and whether it reads as done, merely noted, or gone wrong.
struct BackupResultNote: Equatable {
    enum Tone { case success, neutral, failure }
    let text: String
    let tone: Tone
}

@Observable @MainActor
final class SettingsViewModel {
    private static let logger = Logger.settings

    // MARK: - UI State
    var restoreMode: BackupService.RestoreMode = .merge
    var backupProgress: Double = 0
    var backupMessage: String = ""
    var importProgress: Double = 0
    var importMessage: String = ""
    var resultSummary: BackupResultNote?
    var operationSummary: BackupOperationSummary?
    var restorePreviewData: RestorePreview?
    var defaultFolderName: String = ""
    /// A finished backup in the temporary folder, for the iOS file exporter
    /// when the backup folder couldn't take it: the exporter copies the file,
    /// never reading it into memory. Removed once the exporter is done.
    var exportFileURL: URL?
    /// The notes of the backup at `exportFileURL`, kept until the file
    /// exporter has saved it (`fileExporterFinished`).
    var pendingExportNotes: [String] = []
    /// The message of the backup or restore alert, and its title.
    var importError: String?
    var importErrorTitle = "Couldn't Restore"
    var estimatedBackupSize: Int64?

    // Internal
    /// The notebook backups are made of and restored into: the guide's own
    /// (`DataManagementGrid` makes this view model with it).
    let dependencies: AppDependencies
    var coordinator: BackupCoordinator { dependencies.backupCoordinator }
    private var pendingImportURL: URL?
    /// Restore Now was pressed on the preview: the restore starts once the
    /// sheet has gone (`restorePreviewDismissed`).
    private var restoreConfirmed = false
    
    // MARK: - Initialization
    
    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Last Backup Date
    private static let lastBackupKey = "LastBackupTimeInterval"
    var lastBackupDate: Date? {
        let t = UserDefaults.standard.double(forKey: Self.lastBackupKey)
        return t > 0 ? Date(timeIntervalSinceReferenceDate: t) : nil
    }
    func setLastBackupNow() {
        UserDefaults.standard.set(Date().timeIntervalSinceReferenceDate, forKey: Self.lastBackupKey)
    }

    /// After a restore: the later of this device's last backup and the one
    /// the restored settings carried. A restore isn't a backup, so it never
    /// says "Last backup just now" (that hid the "backup is N days old"
    /// warning), and an older backup's settings don't turn the clock back.
    private func keepLastBackupDate(atLeast earlier: Date?) {
        guard let earlier, (lastBackupDate ?? .distantPast) < earlier else { return }
        UserDefaults.standard.set(earlier.timeIntervalSinceReferenceDate, forKey: Self.lastBackupKey)
    }

    // MARK: - Helpers
    func defaultBackupFilename() -> String {
        "CosmicDaybook_DataBackup_\(DateFormatters.backupFilename.string(from: Date()))"
    }

    func loadDefaultFolderName() {
        if let custom = BackupDestination.resolveBookmarkedFolder() {
            defaultFolderName = custom.lastPathComponent
        } else {
            defaultFolderName = BackupFolderStorage.displayLabel()
        }
    }
    
    /// Calculates estimated backup size asynchronously
    func calculateEstimatedBackupSize(viewContext: NSManagedObjectContext) {
        Task {
            estimatedBackupSize = coordinator.estimateBackupSize(viewContext: viewContext)
        }
    }

    // MARK: - Restore Quick Action

    /// Locates the most recent auto-backup file (any device's, across the
    /// user-chosen folder and the legacy Documents/Backups/Auto path) and runs
    /// it through the preview pipeline. The user still has to confirm in the
    /// preview sheet before the restore actually happens.
    /// Returns `true` if a candidate was found and presented; `false` if no
    /// auto-backup files exist.
    @discardableResult
    func restoreMostRecentAutoBackup(viewContext: NSManagedObjectContext) async -> Bool {
        guard let newest = coordinator.backupStatus().mostRecentAutoBackupURL else {
            #if os(macOS)
            let when = "each time you quit Cosmic Daybook"
            #else
            let when = "each time you leave Cosmic Daybook"
            #endif
            importErrorTitle = "No Automatic Backup Yet"
            importError = "There's no automatic backup yet. With Automatic backups on, one is saved \(when). " +
                "To restore now, choose Import and pick a backup file."
            return false
        }
        // The newest may be another device's, not downloaded here yet (#18).
        guard let candidate = await downloadedBackup(newest) else {
            importErrorTitle = "Couldn't Download the Backup"
            importError = "The newest automatic backup is still in iCloud and couldn't be downloaded to this " +
                "device. Check that it's online, then try again."
            return true
        }
        await previewImportedURL(viewContext: viewContext, url: candidate)
        return true
    }

    /// How long Restore last automatic backup waits for the newest backup to
    /// download: a backup with photos can be large.
    private static let backupDownloadTimeout: Duration = .seconds(300)

    /// `url` with its bytes on this device, downloading them from iCloud first
    /// (the card's progress bar says so); nil when that failed.
    private func downloadedBackup(_ url: URL) async -> URL? {
        guard UbiquitousFile.needsDownload(url) else { return url }
        importProgress = 0.05
        importMessage = "Downloading the backup from iCloud…"
        defer { importProgress = 0; importMessage = "" }
        return await UbiquitousFile.ensureLocal(url, timeout: Self.backupDownloadTimeout)
    }

    // MARK: - Import / Preview
    func previewImportedURL(viewContext: NSManagedObjectContext, url: URL) async {
        // Said before the preview, so the guide isn't asked to confirm a
        // restore that would be refused (`BackupCoordinator.importBackup`
        // refuses it too).
        if let reason = BackupRestoreGate.blocker(in: viewContext) {
            resultSummary = nil
            importErrorTitle = "Can't Restore"
            importError = reason
            return
        }
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        // A preview that failed part-way left the card's progress bar up.
        defer { importProgress = 0; importMessage = "" }
        do {
            importProgress = 0
            importMessage = "Reading file…"
            resultSummary = nil
            // Coordinator accepts only the current backup format for manual restore.
            let preview = try await coordinator.previewImport(
                viewContext: viewContext,
                from: url,
                mode: restoreMode
            ) { [weak self] p, m in
                self?.importProgress = p
                self?.importMessage = m
            }
            restoreConfirmed = false
            restorePreviewData = preview
            pendingImportURL = url
        } catch {
            showRestoreFailure(error, operation: "read the backup file")
        }
    }

    /// Restore Now on the preview: closes the sheet. The restore starts once
    /// it has gone, so its progress shows on the Backups card and a failure's
    /// alert isn't hidden behind the sheet.
    func confirmRestore() {
        restoreConfirmed = true
        restorePreviewData = nil
    }

    /// The preview sheet has gone: runs the restore Restore Now asked for.
    /// Closed any other way (Cancel, a swipe), nothing is restored.
    func restorePreviewDismissed(viewContext: NSManagedObjectContext) async {
        guard restoreConfirmed else {
            pendingImportURL = nil
            return
        }
        restoreConfirmed = false
        await performImportConfirmed(viewContext: viewContext)
    }

    func performImportConfirmed(viewContext: NSManagedObjectContext) async {
        guard let url = pendingImportURL else { return }
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        // However it ends: a restore that failed part-way left the card's
        // progress bar up, and Import and Restore off, until a relaunch.
        defer { importProgress = 0; importMessage = "" }
        let lastBackupBeforeRestore = lastBackupDate
        do {
            importProgress = 0
            importMessage = "Starting…"
            resultSummary = nil
            let summary = try await coordinator.importBackup(
                viewContext: viewContext,
                from: url,
                mode: restoreMode
            ) { [weak self] p, m in
                self?.importProgress = p
                self?.importMessage = m
            }
            restorePreviewData = nil
            pendingImportURL = nil
            importError = nil
            keepLastBackupDate(atLeast: lastBackupBeforeRestore)
            resultSummary = BackupResultNote(text: "Restore complete.", tone: .success)
            operationSummary = BackupOperationSummary(
                kind: .import,
                fileName: summary.fileName,
                formatVersion: summary.formatVersion,
                encryptUsed: summary.encryptUsed,
                createdAt: summary.createdAt,
                entityCounts: summary.entityCounts,
                warnings: summary.warnings,
                notes: summary.notes
            )
        } catch {
            showRestoreFailure(error, operation: "restore your backup")
        }
    }

    // MARK: - Error Handling Helpers

    /// The backup alert: a plain message, with the raw error in the log.
    func showBackupFailure(_ error: Error, operation: String) {
        let raw = String(describing: error)
        Self.logger.error("Backup failed (\(operation, privacy: .public)): \(raw, privacy: .public)")
        importErrorTitle = "Couldn't Save the Backup"
        importError = AppErrorMessages.backupMessage(for: error, operation: operation)
    }

    /// The restore alert: a plain message, with the raw error in the log.
    func showRestoreFailure(_ error: Error, operation: String) {
        let raw = String(describing: error)
        Self.logger.error("Restore failed (\(operation, privacy: .public)): \(raw, privacy: .public)")
        importErrorTitle = "Couldn't Restore"
        importError = AppErrorMessages.backupMessage(for: error, operation: operation)
    }

    func safeRemoveItem(at url: URL, context: String = #function) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where
            (error.domain == NSPOSIXErrorDomain && error.code == 2) ||
            (error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError) {
            // File already gone — nothing to clean up.
        } catch {
            Self.logger.warning(
                "Failed to remove item at \(url.lastPathComponent, privacy: .public): \(error, privacy: .public)"
            )
        }
    }
}
