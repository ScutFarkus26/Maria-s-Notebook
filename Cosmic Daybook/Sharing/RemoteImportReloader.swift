import Foundation
import CoreData

/// Reloads a screen once CloudKit imports into one store settle.
///
/// A screen that builds its rows with a one-off fetch (rather than a
/// `@FetchRequest`) doesn't see records that arrive from iCloud until
/// something reloads it. On 2026-09-28 the Daybook Assistant sat on "No
/// students yet" with the whole class already in its store until the
/// assistant tapped Check Again. A first download arrives as a burst of import
/// events, so each finished import restarts a short wait and the reload runs
/// once when the burst ends. While `isPaused` (a sheet is editing one of the
/// rows) a due reload is held and runs when the pause lifts.
///
/// Nothing reloads while the app is off screen. From `appLeft()` (the
/// background, Control Center, Siri over the app) a due reload is held, and
/// `appReturned()` drops it: the owner reloads everything on the way back
/// (`AssistantReloadOnReturn`, `RestockFollowsScene`), and that one load shows
/// what arrived. Until 2026-10-10 every finished import reloaded in the
/// background too: about 12–15 fetches for the attendance screen and a full
/// Restock load each time, with nobody looking.
///
/// The Daybook Assistant compiles this file by path and targets iOS 18, so it
/// uses the classic `eventChangedNotification`, not the iOS 27 typed messages.
@MainActor
final class RemoteImportReloader {

    /// Waits out `delay`. Tests pass one that returns at once, so they don't
    /// hang on a real 30 ms sleep that a busy simulator can stretch past 10 s.
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let delay: Duration
    private let sleep: Sleep
    private let reload: @MainActor () -> Void
    private var pending: Task<Void, Never>?
    /// A reload came due while paused or away, and waits.
    private(set) var hasHeldReload = false
    /// Between `appLeft()` and `appReturned()`.
    private(set) var isAway = false

    /// While true, a due reload waits; setting it back to false runs it. Away,
    /// it waits on: the return's own load shows it.
    var isPaused = false {
        didSet {
            guard !isPaused, !isAway, hasHeldReload else { return }
            hasHeldReload = false
            reload()
        }
    }

    init(
        delay: Duration = .seconds(1),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        reload: @escaping @MainActor () -> Void
    ) {
        self.delay = delay
        self.sleep = sleep
        self.reload = reload
    }

    deinit {
        pending?.cancel()
    }

    /// An import finished: reload after `delay`, restarting the wait if
    /// another import finishes first.
    func importFinished() {
        pending?.cancel()
        let delay = delay
        let sleep = sleep
        pending = Task { [weak self] in
            try? await sleep(delay)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
    }

    /// The app left the screen: a reload that comes due is held, not run.
    func appLeft() {
        isAway = true
    }

    /// The app is back, and its owner reloads everything now. A reload held
    /// meanwhile (a sheet's hold too: the return's load doesn't wait for the
    /// sheet), or one still settling from an import that already finished,
    /// would only run that load again, so both go. Imports that finish from
    /// here on reload as usual.
    func appReturned() {
        isAway = false
        hasHeldReload = false
        pending?.cancel()
        pending = nil
    }

    /// Feeds every finished import into the store with `storeIdentifier` to
    /// `importFinished` until the calling task is cancelled (a view's `.task`).
    func observeImports(into storeIdentifier: String) async {
        let imports = NotificationCenter.default
            .notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
            .compactMap { Self.isFinishedImport($0, storeIdentifier: storeIdentifier) ? true : nil }
        for await _ in imports {
            importFinished()
        }
    }

    private func fire() {
        if isPaused || isAway {
            hasHeldReload = true
        } else {
            reload()
        }
    }

    /// Read off the notification before it reaches the main actor:
    /// `Notification` isn't Sendable.
    nonisolated static func isFinishedImport(_ note: Notification, storeIdentifier: String) -> Bool {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
        else { return false }
        return isFinishedImport(
            type: event.type, ended: event.endDate != nil, succeeded: event.succeeded,
            eventStore: event.storeIdentifier, storeIdentifier: storeIdentifier
        )
    }

    /// Whether an event is an import into the store with `storeIdentifier`
    /// that finished and worked. A failed one (offline, a quota, a conflict)
    /// counted too until 2026-10-10; CloudKit tries it again, and the try that
    /// works reloads. Pure, for the tests: an event can't be made in one.
    nonisolated static func isFinishedImport(
        type: NSPersistentCloudKitContainer.EventType,
        ended: Bool,
        succeeded: Bool,
        eventStore: String,
        storeIdentifier: String
    ) -> Bool {
        type == .import && ended && succeeded && eventStore == storeIdentifier
    }
}
