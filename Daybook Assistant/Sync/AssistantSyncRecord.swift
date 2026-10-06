import Foundation
import CoreData
import Observation

/// What the sync line (`AssistantSyncStatusView`) goes by: when the shared
/// store last saved, when its last successful export began and import
/// ended, and whether its last export failed.
///
/// Recorded for as long as the app runs, beside `UnsentChangesKeepAlive`
/// (`AssistantStack`), not by the line itself. The line's own listeners
/// heard nothing while it was off screen: a Siri mark made with the app
/// closed never counted as saved, so it read "All marks sent" while still
/// on the phone, and an export that finished during a visit to Restock was
/// missed, so it stuck on "Sending to iCloud…".
///
/// The times are kept across launches: marks saved just before the app was
/// closed are still unsent until the next launch's export says otherwise.
/// They describe one store's sync, so like every such key they are per
/// CloudKit environment: a Development build on the same iPhone keeps its
/// own.
@MainActor
@Observable
final class AssistantSyncRecord {
    static var lastSharedSaveKey: String { CloudKitEnvironment.scoped("Assistant.lastSharedSave") }
    static var lastSharedExportStartKey: String { CloudKitEnvironment.scoped("Assistant.lastSharedExportStart") }
    static var lastSharedImportEndKey: String { CloudKitEnvironment.scoped("Assistant.lastSharedImportEnd") }

    /// Seconds since 1970, 0 for never.
    private(set) var lastSave: Double = 0
    private(set) var lastExportStart: Double = 0
    /// The guide's changes (and the class) as of then. Pull-to-refresh only
    /// re-reads this iPhone, so this is how she knows how fresh it is.
    private(set) var lastImportEnd: Double = 0
    /// For this launch only: the line says the marks go once she's online.
    private(set) var lastExportFailed = false

    private let defaults: UserDefaults
    /// Written in `init` only; read again in `deinit`.
    @ObservationIgnored private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

    init(viewContext: NSManagedObjectContext, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
        let center = NotificationCenter.default
        // Delivered on the saving thread (the main one, for the view
        // context), as the keep-alive's is.
        observers.append(center.addObserver(
            forName: .NSManagedObjectContextDidSave, object: viewContext, queue: nil
        ) { [weak self] note in
            guard UnsentChangesKeepAlive.leavesSomethingToSend(UnsentChangesKeepAlive.changedObjects(in: note))
            else { return }
            let now = Date()
            MainActor.assumeIsolated { self?.saved(at: now) }
        })
        observers.append(center.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let event = Self.finishedSharedEvent(in: note) else { return }
            MainActor.assumeIsolated { self?.record(event) }
        })
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    /// One finished export or import of the shared store.
    nonisolated struct FinishedEvent: Sendable, Equatable {
        var isExport: Bool
        var start: Date
        var end: Date
        var succeeded: Bool
    }

    func saved(at date: Date) {
        lastSave = date.timeIntervalSince1970
        defaults.set(lastSave, forKey: Self.lastSharedSaveKey)
    }

    func record(_ event: FinishedEvent) {
        if event.isExport {
            lastExportFailed = !event.succeeded
            guard event.succeeded else { return }
            // Only moves forward: a late event for an earlier export doesn't
            // take it back.
            let start = event.start.timeIntervalSince1970
            guard start > lastExportStart else { return }
            lastExportStart = start
            defaults.set(start, forKey: Self.lastSharedExportStartKey)
        } else {
            let end = event.end.timeIntervalSince1970
            guard event.succeeded, end > lastImportEnd else { return }
            lastImportEnd = end
            defaults.set(end, forKey: Self.lastSharedImportEndKey)
        }
    }

    /// Reads the kept times again: after `forget(defaults:)`.
    func reload() {
        lastSave = defaults.double(forKey: Self.lastSharedSaveKey)
        lastExportStart = defaults.double(forKey: Self.lastSharedExportStartKey)
        lastImportEnd = defaults.double(forKey: Self.lastSharedImportEndKey)
        lastExportFailed = false
    }

    /// The class came off this iPhone (`AssistantClassroomLocalState.forget`):
    /// its times go, from `defaults` and from the open stack's record.
    static func forget(defaults: UserDefaults) {
        for key in [lastSharedSaveKey, lastSharedExportStartKey, lastSharedImportEndKey] {
            defaults.removeObject(forKey: key)
        }
        if let live = AssistantStack.syncRecord, live.defaults === defaults { live.reload() }
    }

    /// The shared store's finished export or import in `note`, if it says
    /// one finished. Read off the notification before it reaches the main
    /// actor: `Notification` isn't Sendable.
    nonisolated static func finishedSharedEvent(in note: Notification) -> FinishedEvent? {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
              event.type == .export || event.type == .import,
              let end = event.endDate
        else { return nil }
        // Her marks go to the classroom share: the private store's events
        // say nothing about them.
        let container = note.object as? NSPersistentCloudKitContainer
        let configuration = container?.persistentStoreCoordinator.persistentStores
            .first { $0.identifier == event.storeIdentifier }?.configurationName
        guard configuration == CoreDataStack.sharedConfiguration else { return nil }
        return FinishedEvent(
            isExport: event.type == .export, start: event.startDate, end: end, succeeded: event.succeeded
        )
    }
}
