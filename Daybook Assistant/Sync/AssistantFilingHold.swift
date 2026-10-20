import Foundation
import CoreData
import CloudKit
import OSLog

/// Whether her marks may go into the classroom share now, read from the
/// classroom share store's own CloudKit events.
///
/// `container.share(_:to:)` on a store whose CloudKit setup failed, or whose
/// mirroring delegate died, can raise an exception no Swift `catch` traps.
/// The attacher only knew of a stop its own earlier attach had found, so
/// Siri's marks went to `share(_:to:)` on a store whose setup had just failed
/// (2026-10-10 review, #1). Now a failed setup of that store, for any reason
/// (the account and the network included), or an import or export that says
/// its delegate died, holds filing until an import or export of it that
/// began later succeeds. Only the classroom share's store counts: her marks
/// go there, and the private store's events say nothing about them.
///
/// The attacher asks before each pass, and each attach before each chunk
/// (`ClassroomShareAttach.Steps.stopReason`); when the hold lifts, what
/// waits is tried at once (`onLift`). One per stack (`AssistantStack`), so a
/// rebuilt stack starts with none, listening from before its stores open:
/// a setup that fails at once is heard too.
@MainActor
final class AssistantFilingHold {
    private static let logger = Logger.app(category: "filingHold")

    /// Why filing waits, as the end of "…couldn't be added because …" (logged).
    nonisolated static let reason = "iCloud isn't ready to send marks yet"

    /// One finished event of the classroom share's store.
    nonisolated struct Event: Sendable, Equatable {
        var type: NSPersistentCloudKitContainer.EventType
        var succeeded: Bool
        /// The error says the mirroring delegate died (`ClassroomShareAttach`).
        var killedDelegate: Bool
        var start: Date
        var storeIdentifier: String
        /// The error says there was no usable iCloud account to set up with.
        var accountUnavailable = false
    }

    /// Held stores, by identifier, and the start of the latest failure.
    private(set) var heldSince: [String: Date] = [:]
    /// Told when the last hold lifts.
    var onLift: (@MainActor () -> Void)?
    /// The store's setup failed for want of a usable iCloud account, at
    /// least once on this stack. Never cleared, unlike the hold: an import
    /// can work once the account arrives while sharing never does on that
    /// container, so the bootstrapper rebuilds it (bug hunt 2026-10-20 #9).
    private(set) var setupFailedForAccount = false
    /// Told the first time `setupFailedForAccount` is set.
    var onSetupFailedForAccount: (@MainActor () -> Void)?
    /// Written in `listen` only; read again in `deinit`.
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    /// Why filing waits now, or nil.
    var stopReason: String? { heldSince.isEmpty ? nil : Self.reason }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// Follows CloudKit's events from now on.
    func listen() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = Self.sharedStoreEvent(in: note) else { return }
            MainActor.assumeIsolated { self?.follow(event) }
        }
    }

    /// One finished event: a failed setup, or a failure that killed the
    /// delegate, holds its store as of the event's start; a successful import
    /// or export that began after that lifts it.
    func follow(_ event: Event) {
        let store = event.storeIdentifier
        if event.succeeded {
            guard event.type == .import || event.type == .export,
                  let since = heldSince[store], event.start > since else { return }
            heldSince[store] = nil
            guard heldSince.isEmpty else { return }
            Self.logger.notice("The classroom share synced again: waiting marks go in")
            onLift?()
        } else if event.type == .setup || event.killedDelegate {
            heldSince[store] = max(heldSince[store] ?? event.start, event.start)
            Self.logger.notice("The classroom share's sync failed to start or stopped: marks wait")
            if event.type == .setup, event.accountUnavailable, !setupFailedForAccount {
                setupFailedForAccount = true
                onSetupFailedForAccount?()
            }
        }
    }

    /// The classroom share store's finished event in `note`, if it says one
    /// finished. Read off the notification before it reaches the main actor:
    /// `Notification` isn't Sendable.
    nonisolated static func sharedStoreEvent(in note: Notification) -> Event? {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
              event.endDate != nil
        else { return nil }
        let storeID = event.storeIdentifier
        let container = note.object as? NSPersistentCloudKitContainer
        let configuration = container?.persistentStoreCoordinator.persistentStores
            .first { $0.identifier == storeID }?.configurationName
        guard configuration == CoreDataStack.sharedConfiguration else { return nil }
        let killed = (event.error as NSError?).map(ClassroomShareAttach.indicatesDeadMirroringDelegate) ?? false
        return Event(
            type: event.type, succeeded: event.succeeded, killedDelegate: killed,
            start: event.startDate, storeIdentifier: storeID,
            accountUnavailable: (event.error as NSError?).map(isAccountUnavailable) ?? false
        )
    }

    /// Whether `error`, or one it wraps, says there was no usable iCloud
    /// account: Core Data's 134400 ("Unable to initialize without an iCloud
    /// account", with none signed in or one not ready yet), or CloudKit's
    /// not-authenticated or account-temporarily-unavailable. A network
    /// failure isn't one: the container sets up again by itself.
    nonisolated static func isAccountUnavailable(_ error: NSError) -> Bool {
        var current: NSError? = error
        for _ in 0..<5 {
            guard let checked = current else { return false }
            if checked.domain == NSCocoaErrorDomain, checked.code == 134_400 { return true }
            if checked.domain == CKErrorDomain, let code = CKError.Code(rawValue: checked.code),
               code == .notAuthenticated || code == .accountTemporarilyUnavailable { return true }
            current = checked.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }
}
