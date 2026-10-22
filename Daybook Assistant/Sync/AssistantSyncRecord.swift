import Foundation
import CoreData
import Observation

/// What the sync line (`AssistantSyncStatusView`) goes by: when the shared
/// store last saved something only Core Data's own upload can carry, when
/// its last successful export began and import ended, and whether its last
/// export failed, and why.
///
/// A new mark doesn't wait for that upload: the share step
/// (`AssistantShareAttacher`) puts it into the classroom share itself and
/// counts it until it's in. Only an edit or a removal of a record already
/// there goes by Core Data's export, so only such a save is recorded here
/// (`UnsentChangesKeepAlive.leavesSomethingToUpload`). Every save used to
/// count, and on a Wi-Fi that blocks iCloud the line said "Not sent yet"
/// all morning while every mark had reached the guide (2026-10-22).
///
/// Recorded for as long as the app runs, beside `UnsentChangesKeepAlive`
/// (`AssistantStack`), not by the line itself. The line's own listeners
/// heard nothing while it was off screen: a Siri mark made with the app
/// closed never counted as saved, so it read "All marks sent" while still
/// on the phone, and an export that finished during a visit to Restock was
/// missed, so it stuck on "Sending to iCloud…".
///
/// The times are kept across launches: an edit saved just before the app
/// was closed is still unsent until the next launch's export says otherwise.
/// They describe one store's sync, so like every such key they are per
/// CloudKit environment: a Development build on the same iPhone keeps its
/// own.
@MainActor
@Observable
final class AssistantSyncRecord {
    static var lastSharedEditSaveKey: String { CloudKitEnvironment.scoped("Assistant.lastSharedEditSave") }
    static var lastSharedExportStartKey: String { CloudKitEnvironment.scoped("Assistant.lastSharedExportStart") }
    static var lastSharedImportEndKey: String { CloudKitEnvironment.scoped("Assistant.lastSharedImportEnd") }
    /// Where every save's time was kept before new marks stopped counting
    /// (2026-10-22). Dropped on sight: a value left from then would hold the
    /// line on "Sending" until an export, which the share step doesn't need.
    private static var retiredSaveKey: String { CloudKitEnvironment.scoped("Assistant.lastSharedSave") }

    /// Seconds since 1970, 0 for never.
    private(set) var lastEditSave: Double = 0
    private(set) var lastExportStart: Double = 0
    /// The guide's changes (and the class) as of then. Pull-to-refresh only
    /// re-reads this iPhone, so this is how she knows how fresh it is.
    private(set) var lastImportEnd: Double = 0
    /// Why the last export failed, or nil when it succeeded or none has run.
    /// For this launch only.
    private(set) var lastExportFailure: ExportFailure?
    /// Told of each successful export or import of the shared store: proof
    /// iCloud can be reached, so marks waiting offline are tried
    /// (`AssistantStack`).
    @ObservationIgnored var onSharedStoreSynced: (@MainActor () -> Void)?

    /// Why an export failed. The line says marks wait for a network only
    /// for `.network`; blaming being offline for every failure sent her
    /// looking for a signal she had.
    enum ExportFailure: Equatable, Sendable {
        /// iCloud couldn't be reached (`ClassroomShareAttach.indicatesNoConnection`).
        case network
        /// Anything else: Core Data tries again by itself.
        case other
    }

    private let defaults: UserDefaults
    /// Written in `init` only; read again in `deinit`.
    @ObservationIgnored private nonisolated(unsafe) var observers: [any NSObjectProtocol] = []

    init(viewContext: NSManagedObjectContext, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.removeObject(forKey: Self.retiredSaveKey)
        reload()
        let center = NotificationCenter.default
        // Delivered on the saving thread (the main one, for the view
        // context), as the keep-alive's is.
        observers.append(center.addObserver(
            forName: .NSManagedObjectContextDidSave, object: viewContext, queue: nil
        ) { [weak self] note in
            guard UnsentChangesKeepAlive.leavesSomethingToUpload(in: note) else { return }
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
        /// A failure that was iCloud being out of reach.
        var noConnection = false
    }

    /// An edit saved to the shared store with no upload begun after it:
    /// kept across launches, so Leave can warn of changes saved before a
    /// relaunch that never went (`AssistantBootstrapper.unsentMarks`). New
    /// marks are the share step's to count (`AssistantShareAttacher.pending`).
    var hasUnsentSave: Bool { lastEditSave > lastExportStart }

    /// An edit or a removal was saved: something only the upload carries.
    func saved(at date: Date) {
        lastEditSave = date.timeIntervalSince1970
        defaults.set(lastEditSave, forKey: Self.lastSharedEditSaveKey)
    }

    func record(_ event: FinishedEvent) {
        if event.succeeded { onSharedStoreSynced?() }
        if event.isExport {
            lastExportFailure = event.succeeded ? nil : (event.noConnection ? .network : .other)
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
        lastEditSave = defaults.double(forKey: Self.lastSharedEditSaveKey)
        lastExportStart = defaults.double(forKey: Self.lastSharedExportStartKey)
        lastImportEnd = defaults.double(forKey: Self.lastSharedImportEndKey)
        lastExportFailure = nil
    }

    /// The class came off this iPhone (`AssistantClassroomLocalState.forget`):
    /// its times go, from `defaults` and from the open stack's record.
    static func forget(defaults: UserDefaults) {
        for key in [lastSharedEditSaveKey, lastSharedExportStartKey, lastSharedImportEndKey, retiredSaveKey] {
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
        let noConnection = event.error.map { ClassroomShareAttach.indicatesNoConnection($0 as NSError) } ?? false
        return FinishedEvent(
            isExport: event.type == .export, start: event.startDate, end: end, succeeded: event.succeeded,
            noConnection: noConnection
        )
    }
}
