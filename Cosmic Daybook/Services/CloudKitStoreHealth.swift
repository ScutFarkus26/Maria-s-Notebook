import CloudKit
import CoreData
import Foundation

// MARK: - Per-store sync health
//
// The notebook mirrors two stores, each with its own mirroring delegate: the
// private store (the notebook) and the classroom share. One store's delegate
// can stop for good while the other keeps syncing. On 2026-09-30 the classroom
// share's export was refused by the Production schema ("Cannot create new type
// CD_AttendanceEmailSettings in production schema"), its delegate reset and
// never initialized again, and the notebook's next successful import cleared
// the one global error — so Settings and `sync_status` said "healthy" for
// hours. Failures are therefore kept per store and per event kind, and only a
// later successful event of the same kind on the same store clears one.

/// Which mirrored store an `NSPersistentCloudKitContainer.Event` belongs to.
nonisolated enum SyncedStore: Hashable, Sendable {
    /// The private store: the guide's own notebook.
    case notebook
    /// The shared store: the classroom share the assistant also syncs.
    case classroomShare
    /// A store this app does not recognize (or an event without a store).
    case other

    init(identifier: String?, notebookIdentifier: String?, classroomShareIdentifier: String?) {
        switch identifier {
        case .some(let id) where id == notebookIdentifier: self = .notebook
        case .some(let id) where id == classroomShareIdentifier: self = .classroomShare
        default: self = .other
        }
    }

    /// Capitalized, for the start of a message.
    var displayName: String {
        switch self {
        case .notebook: return "Notebook"
        case .classroomShare: return "Classroom share"
        case .other: return "Another store"
        }
    }

    /// Mid-sentence.
    var phrase: String {
        switch self {
        case .notebook: return "the notebook"
        case .classroomShare: return "the classroom share"
        case .other: return "that store"
        }
    }

    /// Order for listing: notebook first.
    fileprivate var sortOrder: Int {
        switch self {
        case .notebook: return 0
        case .classroomShare: return 1
        case .other: return 2
        }
    }
}

/// A failed CloudKit event that no later success of the same kind has cleared.
nonisolated struct StoreSyncFailure: Equatable, Sendable {
    enum Severity: Equatable, Sendable {
        /// A network hiccup, throttling or a busy zone: the container retries on its own.
        case retrying
        /// Setup failed, the delegate is dead, or the server refused the request
        /// (a schema, permission or quota problem). Retrying sends the same thing
        /// and gets the same answer, so the store stays out of sync until someone acts.
        case stopped
    }

    /// Why it failed, as far as the error says. Decides the advice: a refusal
    /// is fixed on the iCloud side, a dead delegate on its own points at this
    /// device's copy (see `SyncStoppedAdvice`).
    enum Cause: Equatable, Sendable {
        /// Network trouble, throttling, a busy zone: the container retries.
        case transient
        /// CloudKit refused the request: a CloudKit code outside
        /// `CloudKitStoreHealth.retryingCodes` (invalid arguments such as a
        /// schema the server doesn't have, a rejected request, permission,
        /// quota). Re-downloading sends the same thing and gets the same answer.
        case serverRefusal(ckCode: Int)
        /// Core Data's mirroring delegate died (134421, 134406, "never
        /// successfully initialized").
        case mirroringDelegateDied
        /// Anything else, or no error at all.
        case other

        var isServerRefusal: Bool {
            if case .serverRefusal = self { return true }
            return false
        }

        /// True when retrying cannot help.
        var stops: Bool {
            switch self {
            case .serverRefusal, .mirroringDelegateDied: return true
            case .transient, .other: return false
            }
        }
    }

    /// `errorCode` of a failed event that carried no error.
    static let noErrorCode = "no code"

    let store: SyncedStore
    let eventType: NSPersistentCloudKitContainer.EventType
    let severity: Severity
    let cause: Cause
    /// What the server (or Core Data) said, verbatim.
    let serverMessage: String
    /// "CKError 12", "NSCocoaErrorDomain 134406", …
    let errorCode: String
    /// When this store first failed this kind of event since its last success.
    let date: Date

    var eventName: String {
        switch eventType {
        case .setup: return "setup"
        case .import: return "import"
        case .export: return "export"
        @unknown default: return "sync"
        }
    }

    /// One line that names the store and quotes the server.
    var message: String {
        let head = "\(store.displayName) \(eventName) failed: \u{201C}\(serverMessage)\u{201D} (\(errorCode))."
        switch severity {
        case .stopped: return head + " Nothing in \(store.phrase) syncs until this is fixed."
        case .retrying: return head + " iCloud will try again."
        }
    }
}

/// Outstanding failures and last successes, per store and event kind.
nonisolated struct CloudKitStoreHealth: Equatable, Sendable {
    private struct Key: Hashable, Sendable {
        let store: SyncedStore
        let eventType: NSPersistentCloudKitContainer.EventType
    }

    private var failures: [Key: StoreSyncFailure] = [:]
    /// When each store last finished any event successfully.
    private(set) var lastSuccess: [SyncedStore: Date] = [:]

    /// Records a finished event. A failure replaces any earlier failure of the
    /// same kind on that store, keeping the first one's date (the store has been
    /// failing since then); a success clears it. A server refusal is the one
    /// exception: the dead delegate and retries that follow it are its
    /// symptoms, so they don't replace it (on 2026-09-30 the schema refusal was
    /// followed by "never successfully initialized", which on its own reads as
    /// a damaged local store).
    mutating func recordFinishedEvent(
        store: SyncedStore,
        type: NSPersistentCloudKitContainer.EventType,
        succeeded: Bool,
        error: (any Error)?,
        at date: Date = Date()
    ) {
        let key = Key(store: store, eventType: type)
        if succeeded {
            failures[key] = nil
            lastSuccess[store] = date
            return
        }
        let detail = error.map(Self.detail(of:))
        if failures[key]?.cause.isServerRefusal == true, detail?.cause.isServerRefusal != true { return }
        let severity: StoreSyncFailure.Severity = (type == .setup || detail?.stops == true) ? .stopped : .retrying
        failures[key] = StoreSyncFailure(
            store: store,
            eventType: type,
            severity: severity,
            cause: detail?.cause ?? .other,
            serverMessage: detail?.message ?? "No error was given",
            errorCode: detail?.code ?? StoreSyncFailure.noErrorCode,
            date: failures[key]?.date ?? date
        )
    }

    /// Outstanding failures, stopped ones first, then notebook before classroom share.
    var outstandingFailures: [StoreSyncFailure] {
        failures.values.sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity == .stopped }
            if lhs.store != rhs.store { return lhs.store.sortOrder < rhs.store.sortOrder }
            return lhs.eventType.rawValue < rhs.eventType.rawValue
        }
    }

    /// The failure that decides overall health, if any.
    var mostSevereFailure: StoreSyncFailure? { outstandingFailures.first }

    /// Stores that have had any event this session, notebook first.
    var knownStores: [SyncedStore] {
        Set(lastSuccess.keys).union(failures.keys.map(\.store)).sorted { $0.sortOrder < $1.sortOrder }
    }

    func failures(for store: SyncedStore) -> [StoreSyncFailure] {
        outstandingFailures.filter { $0.store == store }
    }

    // MARK: - Reading the error

    /// Transient CloudKit codes: the container retries these by itself. Any
    /// other CloudKit code is a refusal.
    static let retryingCodes: Set<CKError.Code> = [
        .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited,
        .zoneBusy, .operationCancelled, .serverRecordChanged, .changeTokenExpired, .unknownItem,
        .limitExceeded, .assetFileModified, .accountTemporarilyUnavailable, .batchRequestFailed,
        .partialFailure, .internalError
    ]

    struct Detail: Equatable, Sendable {
        let message: String
        let code: String
        let cause: StoreSyncFailure.Cause
        /// True when retrying cannot help.
        var stops: Bool { cause.stops }
    }

    /// The most telling leaf of `error`. A partial failure's per-record errors
    /// and underlying errors are opened up; then a server refusal wins (it is
    /// the cause when Core Data wraps it in a dead-delegate error), then any
    /// other leaf that stops sync, then a CloudKit leaf other than
    /// `batchRequestFailed` (which only says another record in the batch
    /// failed), then anything.
    static func detail(of error: any Error) -> Detail {
        let leaves = leafErrors(of: error as NSError)
        let pick = leaves.first { leafDetail($0).cause.isServerRefusal }
            ?? leaves.first { leafDetail($0).stops }
            ?? leaves.first { $0.domain == CKErrorDomain && $0.code != CKError.Code.batchRequestFailed.rawValue }
            ?? leaves.first
            ?? (error as NSError)
        return leafDetail(pick)
    }

    private static func leafErrors(of error: NSError, depth: Int = 0) -> [NSError] {
        guard depth < 4 else { return [error] }
        if error.domain == CKErrorDomain,
           let partial = error.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: any Error],
           !partial.isEmpty {
            // Dictionary order is random; sort so the same error reads the same way twice.
            let inner = partial.values.map { $0 as NSError }
                .sorted { ($0.code, $0.localizedDescription) < ($1.code, $1.localizedDescription) }
            return inner.flatMap { leafErrors(of: $0, depth: depth + 1) }
        }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            // Keep the wrapper too: Core Data's own codes (134406…) live on it.
            return [error] + leafErrors(of: underlying, depth: depth + 1)
        }
        return [error]
    }

    private static func leafDetail(_ error: NSError) -> Detail {
        // CKError keeps the server's own words under "ServerErrorDescription";
        // localizedDescription is usually the same text, sometimes a generic one.
        let server = (error.userInfo["ServerErrorDescription"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let message = server ?? error.localizedDescription
        if error.domain == CKErrorDomain {
            let retries = CKError.Code(rawValue: error.code).map(retryingCodes.contains) ?? false
            return Detail(
                message: message,
                code: "CKError \(error.code)",
                cause: retries ? .transient : .serverRefusal(ckCode: error.code)
            )
        }
        let delegateDead = error.domain == NSCocoaErrorDomain && (error.code == 134421 || error.code == 134406)
        let neverInitialized = message.range(of: "never successfully initialized", options: .caseInsensitive) != nil
        return Detail(
            message: message,
            code: "\(error.domain) \(error.code)",
            cause: delegateDead || neverInitialized ? .mirroringDelegateDied : .other
        )
    }
}
