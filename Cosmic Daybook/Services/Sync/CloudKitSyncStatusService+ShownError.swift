import CoreData
import Foundation
import OSLog

// MARK: - The shown sync error
//
// Settings, the toolbar dot and Sync History say what went wrong in plain
// words. The raw form (the system error with its domain and code) is kept
// beside it — `lastSyncErrorDetail`, a history row's `detail` — for the
// Details disclosure and `sync_status`, never in the message itself.

extension CloudKitSyncStatusService {

    /// What kind of problem `lastSyncError` is.
    enum SyncErrorKind: String, Sendable {
        case network
        case account
        case other
    }

    /// What an error saved before errors had kinds (2026-10-03) shows: that
    /// text was the raw form, so it becomes the detail under this. Also what
    /// a failed event that isn't iCloud's or the network's says.
    static let legacySyncErrorMessage = "iCloud sync didn't finish. It'll try again on its own."

    /// Records the error Settings shows: the plain `message`, the raw
    /// `detail` behind it, and its kind. Persisted unless `persist` is false,
    /// so the next launch still shows it until a sync succeeds.
    func recordSyncError(_ message: String, detail: String?, kind: SyncErrorKind, persist: Bool = true) {
        lastSyncError = message
        lastSyncErrorDetail = detail
        lastSyncErrorKind = kind
        guard persist else { return }
        let defaults = UserDefaults.standard
        defaults.set(message, forKey: UserDefaultsKeys.cloudKitLastSyncError)
        defaults.set(detail, forKey: UserDefaultsKeys.cloudKitLastSyncErrorDetail)
        defaults.set(kind.rawValue, forKey: UserDefaultsKeys.cloudKitLastSyncErrorKind)
    }

    /// Clears the shown error in memory. Writes only what changed: `@Observable`
    /// notifies on every assignment, and the toolbar dot observes this service.
    func clearSyncErrorInMemory() {
        if lastSyncError != nil { lastSyncError = nil }
        if lastSyncErrorDetail != nil { lastSyncErrorDetail = nil }
        if lastSyncErrorKind != nil { lastSyncErrorKind = nil }
    }

    /// Removes the persisted copy of the shown error.
    static func removePersistedSyncError(from defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncError)
        defaults.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncErrorDetail)
        defaults.removeObject(forKey: UserDefaultsKeys.cloudKitLastSyncErrorKind)
    }

    /// Reads the shown error the last launch persisted (called from `init`).
    /// One saved by an older build has no kind: its text was raw, so it shows
    /// as the plain general sentence with the old text as its detail, and its
    /// kind is read from the old wording once, here, so coming back online or
    /// signing in still clears it.
    func loadPersistedSyncError() {
        let defaults = UserDefaults.standard
        let stored = defaults.string(forKey: UserDefaultsKeys.cloudKitLastSyncError)
        let kind = defaults.string(forKey: UserDefaultsKeys.cloudKitLastSyncErrorKind)
            .flatMap(SyncErrorKind.init(rawValue:))
        guard let stored, kind == nil else {
            lastSyncError = stored
            lastSyncErrorDetail = defaults.string(forKey: UserDefaultsKeys.cloudKitLastSyncErrorDetail)
            lastSyncErrorKind = kind
            return
        }
        lastSyncError = Self.legacySyncErrorMessage
        lastSyncErrorDetail = stored
        if ["network", "offline", "Waiting"].contains(where: stored.contains) {
            lastSyncErrorKind = .network
        } else if ["iCloud", "signed in", "Sign into"].contains(where: stored.contains) {
            lastSyncErrorKind = .account
        } else {
            lastSyncErrorKind = .other
        }
    }

    // MARK: - Recording failures

    /// A failed CloudKit event: Settings' plain message and Sync History's
    /// line, each with the raw form ("Classroom share export failed
    /// [CKErrorDomain (2)]: …") as its detail. Call after `storeHealth` has
    /// the event, so the line can say whether that store's sync is stopped.
    func recordEventFailure(
        type: NSPersistentCloudKitContainer.EventType,
        store: SyncedStore,
        typeDescription: String,
        error: (any Error)?
    ) {
        let stopped = storeHealth.failures(for: store).first { $0.eventType == type }?.severity == .stopped
        let line = Self.historyLine(failed: type, store: store, stopped: stopped)
        let detail: String
        if let error {
            let nsError = error as NSError
            detail = "\(typeDescription) failed [\(nsError.domain) (\(nsError.code))]: \(nsError.localizedDescription)"
            Self.logger.error("CloudKit \(detail)")
        } else {
            detail = "\(typeDescription) failed: Unknown error"
            Self.logger.error("\(detail)")
        }
        SyncEventLogger.shared.log("cloudkit", status: "error", message: line, detail: detail)
        recordSyncError(
            Self.plainEventFailureMessage(for: error, type: type),
            detail: detail,
            kind: error.map(Self.errorKind(of:)) ?? .other
        )
    }

    /// Sync Now's save failed.
    func recordManualSyncFailure(_ error: any Error) {
        let detail = Self.technicalDetail(of: error)
        recordSyncError(
            AppErrorMessages.userMessage(for: error, context: "syncing with iCloud"),
            detail: detail,
            kind: Self.errorKind(of: error)
        )
        Self.logger.error("Manual sync failed: \(detail, privacy: .public)")
        SyncEventLogger.shared.log("cloudkit", status: "error", message: "Sync Now didn't finish", detail: detail)
    }

    /// The automatic retries ran out: say so once, keeping the detail of what
    /// kept failing for Details.
    func reportRetriesExhausted() {
        recordSyncError(
            "iCloud sync keeps failing. Your changes are safe on this device. Try Sync Now in a little while.",
            detail: lastSyncErrorDetail,
            kind: lastSyncErrorKind ?? .other
        )
        SyncEventLogger.shared.log(
            "cloudkit", status: "error",
            message: "Sync kept failing, so it stopped trying for now",
            detail: "Gave up after \(retryLogic.maxRetryCount) retry attempts"
        )
        updateSyncHealth()
        ToastService.shared.showError(
            "Couldn't sync with iCloud. Your changes are safe on this device.",
            actionLabel: "Retry"
        ) { [weak self] in
            Task { await self?.syncNow() }
        }
    }

    // MARK: - Wording

    /// The raw text of a sync error, for Details and the log.
    static func technicalDetail(of error: any Error) -> String {
        let nsError = error as NSError
        return "\(nsError.localizedDescription) [\(nsError.domain) (\(nsError.code))]"
    }

    /// Whether an error is about the connection, the iCloud account, or something else.
    static func errorKind(of error: any Error) -> SyncErrorKind {
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case (NSURLErrorDomain, _), ("CKErrorDomain", 3), ("CKErrorDomain", 4): return .network
        case ("CKErrorDomain", 9): return .account
        default:
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
                return errorKind(of: underlying)
            }
            return .other
        }
    }

    /// The plain message for a failed CloudKit event. iCloud's and the
    /// network's errors are translated; anything else (Core Data's mirroring
    /// errors) gets a general sentence. The raw text goes to `lastSyncErrorDetail`.
    static func plainEventFailureMessage(
        for error: (any Error)?, type: NSPersistentCloudKitContainer.EventType
    ) -> String {
        if let error {
            let domain = (error as NSError).domain
            if domain == NSURLErrorDomain || domain == "CKErrorDomain" {
                return AppErrorMessages.userMessage(for: error, context: "syncing")
            }
        }
        if type == .setup {
            return "iCloud sync couldn't start. Reopen the app to try again."
        }
        return legacySyncErrorMessage
    }

    /// Sync History's plain line for a finished event.
    static func historyLine(succeeded type: NSPersistentCloudKitContainer.EventType) -> String {
        switch type {
        case .setup: return "iCloud sync started"
        case .import: return "Got changes from iCloud"
        case .export: return "Sent changes to iCloud"
        @unknown default: return "Synced with iCloud"
        }
    }

    /// Sync History's plain line for a failed event; the raw error is the row's detail.
    static func historyLine(
        failed type: NSPersistentCloudKitContainer.EventType, store: SyncedStore, stopped: Bool
    ) -> String {
        let changes = store == .classroomShare ? "classroom share changes" : "changes"
        let base: String
        switch type {
        case .setup:
            return store == .classroomShare ? "Classroom share sync couldn't start" : "iCloud sync couldn't start"
        case .import: base = "Couldn't get \(changes) from iCloud"
        case .export: base = "Couldn't send \(changes)"
        @unknown default: base = "Couldn't sync \(changes)"
        }
        return base + (stopped ? " \u{2014} sync is stopped" : " \u{2014} will try again")
    }
}
