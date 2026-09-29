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
/// The Daybook Assistant compiles this file by path and targets iOS 18, so it
/// uses the classic `eventChangedNotification`, not the iOS 27 typed messages.
@MainActor
final class RemoteImportReloader {

    private let delay: Duration
    private let reload: @MainActor () -> Void
    private var pending: Task<Void, Never>?
    private var heldWhilePaused = false

    /// While true, a due reload waits; setting it back to false runs it.
    var isPaused = false {
        didSet {
            guard !isPaused, heldWhilePaused else { return }
            heldWhilePaused = false
            reload()
        }
    }

    init(delay: Duration = .seconds(1), reload: @escaping @MainActor () -> Void) {
        self.delay = delay
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
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.fire()
        }
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
        if isPaused {
            heldWhilePaused = true
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
        return event.type == .import && event.endDate != nil && event.storeIdentifier == storeIdentifier
    }
}
