import Foundation
import SwiftUI
import OSLog

/// Coordinates database initialization errors and recovery actions.
/// Provides app-wide error state management for database failures.
@Observable
final class DatabaseErrorCoordinator {
    private static let logger = Logger.database
    static let shared = DatabaseErrorCoordinator()
    
    var error: Error?
    var errorDetails: String = ""
    
    private init() {}
    
    /// What the error screen says when nothing more specific is known.
    static let genericMessage = "Cosmic Daybook couldn't open your notebook on this device."

    /// The plain sentence for a launch error: a stack error's own (plain)
    /// description or one the app wrote, never raw system text, which stays
    /// in `errorDetails` for the screen's Details.
    static func userMessage(for error: any Error) -> String {
        if let stackError = error as? CoreDataStackError, let message = stackError.errorDescription {
            return message
        }
        let nsError = error as NSError
        if nsError.domain == "CosmicDaybook", !nsError.localizedDescription.isEmpty {
            return nsError.localizedDescription
        }
        return genericMessage
    }

    /// The plain sentence for the current error.
    var userMessage: String {
        error.map(Self.userMessage(for:)) ?? Self.genericMessage
    }

    /// The raw text of a launch error, for the log and the screen's Details:
    /// a stack error's own facts (store file, format numbers), else the
    /// system text with its domain and code.
    static func technicalDescription(of error: any Error) -> String {
        if let stackError = error as? CoreDataStackError {
            return stackError.technicalDetail
        }
        let nsError = error as NSError
        return "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
    }

    /// Sets a database initialization error. `details` is the raw text the
    /// screen keeps under Details; by default, the error's own.
    func setError(_ error: Error, details: String = "") {
        self.error = error
        self.errorDetails = details.isEmpty ? Self.technicalDescription(of: error) : details
    }
    
    /// Clears the error state
    func clearError() {
        self.error = nil
        self.errorDetails = ""
    }
    
    // MARK: - Recovery

    /// What the screen offers in place of "Re-download from iCloud…".
    enum RedownloadOffer: Equatable {
        /// The button.
        case button
        /// Nothing: re-downloading can't help here, or would do harm.
        case hidden
        /// No button; this sentence says why.
        case unavailable(String)
    }

    /// Why there's no Re-download while iCloud sync is off.
    static let redownloadNeedsSyncMessage = "iCloud sync is off on this device, so there's no copy in iCloud "
        + "to download again. Your notebook here is left as it is."

    /// Re-download throws this device's copy away and downloads the iCloud
    /// one at the next launch. Not offered for a notebook a newer version last
    /// opened (an older copy of the app is the problem, and the download would
    /// land in a store it can't keep), while another copy of the app has the
    /// notebook open (closing it is the fix), or for a damaged app (reinstall).
    /// With iCloud sync off, this device's copy is the only one: the screen
    /// says so instead.
    static func redownloadOffer(for error: (any Error)?, syncPreferred: Bool) -> RedownloadOffer {
        switch error as? CoreDataStackError {
        case .storeFromNewerBuild?, .storeInUseByAnotherCopy?, .modelNotFound?, .restoreUnfinished?:
            return .hidden
        default:
            return syncPreferred ? .button : .unavailable(redownloadNeedsSyncMessage)
        }
    }

    /// What the screen offers for restoring a backup.
    enum RestoreOffer: Equatable {
        /// "Restore from a Backup…", into a fresh notebook (`FreshNotebookRestore`).
        case button
        /// No button; this sentence says how to restore instead.
        case guidance(String)
        /// Nothing: a restore can't help here, or would do harm.
        case hidden
    }

    /// Restoring here puts a backup in place of the notebook that wouldn't
    /// open, which is moved aside and kept (`FreshNotebookRestore`). Not
    /// offered for a notebook a newer version last opened (a restore would
    /// replace its newer data with older), while another copy of the app has
    /// the notebook open, or for a damaged app (it can't read a backup either).
    ///
    /// With iCloud sync on, the notebook in iCloud would download into the
    /// restored one at the next launch and every record would arrive twice.
    /// Re-download is the way back then (it's offered whenever this is), and
    /// a backup restores safely from Settings once the download has finished,
    /// so the screen says that instead.
    static func restoreOffer(for error: (any Error)?, syncPreferred: Bool) -> RestoreOffer {
        switch error as? CoreDataStackError {
        case .storeFromNewerBuild?, .storeInUseByAnotherCopy?, .modelNotFound?, .restoreUnfinished?:
            return .hidden
        default:
            return syncPreferred ? .guidance(FreshNotebookRestore.syncOnGuidance) : .button
        }
    }

    /// Whether the screen says anything about restoring a backup, the button
    /// or how to (`restoreOffer`).
    static func offersRestoreBackup(for error: (any Error)?) -> Bool {
        restoreOffer(for: error, syncPreferred: false) != .hidden
    }

    var redownloadOffer: RedownloadOffer {
        Self.redownloadOffer(for: error, syncPreferred: CoreDataStack.syncPreferred(in: .standard))
    }

    var restoreOffer: RestoreOffer {
        Self.restoreOffer(for: error, syncPreferred: CoreDataStack.syncPreferred(in: .standard))
    }

    /// Whether a restore from this screen is under way, in any window.
    private(set) var isRestoringBackup = false

    /// Restores the backup at `url` in place of the notebook that wouldn't
    /// open (`FreshNotebookRestore`); the caller then quits, and the next
    /// launch opens the restored notebook. Throws, with the old notebook where
    /// it was, when the restore is refused or fails.
    func restoreBackupIntoFreshNotebook(
        from url: URL,
        appRouter: AppRouter,
        progress: @escaping BackupService.ProgressCallback
    ) async throws -> FreshNotebookRestore.Result {
        guard !isRestoringBackup else { throw FreshNotebookRestore.Failure.alreadyRunning }
        isRestoringBackup = true
        defer { isRestoringBackup = false }
        // The file picker's file, outside the app's own folders on iOS, as
        // Settings' restore reads it.
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
        let restore = try FreshNotebookRestore.forThisDevice()
        let coordinator = BackupCoordinator(
            backupService: BackupService(),
            transactionManager: BackupTransactionManager(),
            appRouter: appRouter
        )
        Self.logger.warning("Restoring a backup from the database-error screen into a fresh notebook")
        return try await restore.run(backup: url, restoringWith: coordinator, progress: progress)
    }

    /// What the screen says once the backup is restored.
    static func restoredMessage(warnings: [String]) -> String {
        var lines = [
            "Open Cosmic Daybook again to use your notebook. The notebook that wouldn't open is kept "
                + "on this device, set aside. iCloud sync stays off."
        ]
        lines += warnings
        return lines.joined(separator: "\n\n")
    }

    /// What the screen says when a restore from it didn't happen.
    static func restoreFailureMessage(for error: any Error) -> String {
        AppErrorMessages.backupMessage(for: error, operation: "restore your backup")
    }

    /// Arms "Re-download from iCloud" for the next launch, which destroys the
    /// stores before anything opens them; the caller then quits. Nothing is
    /// deleted here, with the app running. False, and nothing armed, while
    /// iCloud sync is off.
    func armRedownload(defaults: UserDefaults = .standard) -> Bool {
        guard CoreDataStack.armLocalCacheReset(source: "DatabaseErrorView", defaults: defaults) else {
            return false
        }
        Self.logger.warning("Re-download armed from the database-error screen; the app quits now")
        return true
    }

    // Exports diagnostic information about the error
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func exportDiagnostics() -> String {
        var diagnostics: [String] = []
        
        diagnostics.append("=== Database Error Diagnostics ===")
        diagnostics.append("")
        diagnostics.append("Timestamp: \(Date().formatted())")
        diagnostics.append("")
        
        // Error information
        if let error {
            diagnostics.append("Error: \(error.localizedDescription)")
            if let nsError = error as NSError? {
                diagnostics.append("Domain: \(nsError.domain)")
                diagnostics.append("Code: \(nsError.code)")
                if !nsError.userInfo.isEmpty {
                    diagnostics.append("UserInfo: \(nsError.userInfo)")
                }
            }
        } else {
            diagnostics.append("Error: No error information available")
        }
        
        if !errorDetails.isEmpty {
            diagnostics.append("")
            diagnostics.append("Details: \(errorDetails)")
        }
        
        diagnostics.append("")
        diagnostics.append("=== Environment Information ===")
        diagnostics.append("")
        
        // System information
        #if os(macOS)
        diagnostics.append("Platform: macOS")
        diagnostics.append("Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #elseif os(iOS)
        diagnostics.append("Platform: iOS")
        diagnostics.append("Version: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        #else
        diagnostics.append("Platform: Unknown")
        #endif
        
        // App information
        if let bundleID = Bundle.main.bundleIdentifier {
            diagnostics.append("Bundle ID: \(bundleID)")
        }
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            diagnostics.append("App Version: \(version)")
        }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            diagnostics.append("Build: \(build)")
        }
        
        diagnostics.append("")
        diagnostics.append("=== Database Configuration ===")
        diagnostics.append("")
        
        // Store URL
        let storeURL = AppBootstrapping.storeFileURL()
        diagnostics.append("Store URL: \(storeURL.path)")
        let fileManager = FileManager.default
        diagnostics.append("Store exists: \(fileManager.fileExists(atPath: storeURL.path))")
        if fileManager.fileExists(atPath: storeURL.path) {
            diagnostics.append("Store readable: \(fileManager.isReadableFile(atPath: storeURL.path))")
            diagnostics.append("Store writable: \(fileManager.isWritableFile(atPath: storeURL.path))")

            // File size
            do {
                let attrs = try fileManager.attributesOfItem(atPath: storeURL.path)
                if let size = attrs[.size] as? Int64 {
                    let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                    diagnostics.append("Store size: \(sizeStr)")
                }
            } catch {
                diagnostics.append("Store size: Unable to get file size (\(error.localizedDescription))")
            }
        }
        
        // UserDefaults flags
        diagnostics.append("")
        diagnostics.append("=== UserDefaults Flags ===")
        diagnostics.append("")
        let ephemeral = UserDefaults.standard.bool(forKey: UserDefaultsKeys.ephemeralSessionFlag)
        diagnostics.append("Ephemeral Session: \(ephemeral)")
        let ckEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.enableCloudKitSync)
        diagnostics.append("CloudKit Enabled: \(ckEnabled)")
        diagnostics.append("CloudKit Active: \(UserDefaults.standard.bool(forKey: UserDefaultsKeys.cloudKitActive))")
        
        if let lastError = UserDefaults.standard.string(forKey: UserDefaultsKeys.lastStoreErrorDescription) {
            diagnostics.append("Last Error: \(lastError)")
        }
        
        return diagnostics.joined(separator: "\n")
    }
}
