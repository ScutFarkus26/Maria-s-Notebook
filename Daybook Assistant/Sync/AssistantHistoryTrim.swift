import Foundation
@preconcurrency import CoreData
import OSLog

/// Keeps the Assistant's persistent history from growing for good.
///
/// The notebook trims history through `PersistentHistoryProcessor`, which the
/// Assistant leaves out (`CoreDataStack`, `ASSISTANT_APP`), so here nothing
/// did: every save's transaction stayed in both stores. This trims by the
/// notebook's rule: only transactions older than both the start of the
/// store's last successful export (CloudKit's mirroring has sent them;
/// deleting history it hasn't read forces a full re-sync and can bring
/// deleted records back) and 180 days, at most once every 60 days.
///
/// Unlike the notebook, export starts are kept per store and each delete
/// touches only its own store: an export of the private store says nothing
/// about the shared store's history. A store with no recorded export is left
/// alone. Starts are recorded from launch for the life of the app
/// (`recordExports`), not only while the sync line is on screen.
@MainActor
enum AssistantHistoryTrim {
    nonisolated private static let logger = Logger.app(category: "historyTrim")

    /// Apple: long enough for the history to become irrelevant.
    nonisolated static let retention: TimeInterval = 180 * 24 * 3600
    /// Apple: apps only need to purge history several times a year.
    nonisolated static let interval: TimeInterval = 60 * 24 * 3600

    /// Store identifier → start of its last successful export.
    static var exportStartsKey: String { CloudKitEnvironment.scoped("Assistant.historyExportStarts") }
    /// Store identifier → when it was last trimmed.
    static var lastTrimsKey: String { CloudKitEnvironment.scoped("Assistant.historyLastTrims") }

    /// Transactions before this go: before the export's start, and before
    /// the retention window.
    nonisolated static func cutoff(exportStart: Date, now: Date) -> Date {
        min(exportStart, now.addingTimeInterval(-retention))
    }

    /// Kept as seconds since the reference date, which is how a `Date` holds
    /// its time: through 1970 the round trip could come back a hair off.
    static func exportStarts(_ defaults: UserDefaults = .standard) -> [String: Date] {
        let raw = defaults.dictionary(forKey: exportStartsKey) as? [String: TimeInterval] ?? [:]
        return raw.mapValues(Date.init(timeIntervalSinceReferenceDate:))
    }

    /// Only moves forward: a late event for an earlier export doesn't take it back.
    static func recordExport(storeIdentifier: String, startedAt start: Date, defaults: UserDefaults = .standard) {
        var raw = defaults.dictionary(forKey: exportStartsKey) as? [String: TimeInterval] ?? [:]
        guard start.timeIntervalSinceReferenceDate > raw[storeIdentifier] ?? -.infinity else { return }
        raw[storeIdentifier] = start.timeIntervalSinceReferenceDate
        defaults.set(raw, forKey: exportStartsKey)
    }

    /// Records every store's successful exports from now on.
    static func recordExports() -> Task<Void, Never> {
        Task {
            let exports = NotificationCenter.default
                .notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
                .compactMap { finishedExport(in: $0) }
            for await export in exports {
                recordExport(storeIdentifier: export.storeIdentifier, startedAt: export.start)
            }
        }
    }

    /// Trims each of `container`'s stores that has a recorded export and
    /// hasn't been trimmed for 60 days. Returns the stores it trimmed.
    @discardableResult
    static func trim(
        _ container: NSPersistentContainer, defaults: UserDefaults = .standard, now: Date = Date()
    ) async -> [String] {
        let starts = exportStarts(defaults)
        var lastTrims = defaults.dictionary(forKey: lastTrimsKey) as? [String: TimeInterval] ?? [:]
        var trimmed: [String] = []
        for storeID in container.persistentStoreCoordinator.persistentStores.compactMap(\.identifier) {
            guard let start = starts[storeID] else { continue }
            if let last = lastTrims[storeID], now.timeIntervalSince1970 - last < interval { continue }
            let cutoff = cutoff(exportStart: start, now: now)
            guard await deleteHistory(before: cutoff, inStore: storeID, container: container) else { continue }
            lastTrims[storeID] = now.timeIntervalSince1970
            trimmed.append(storeID)
            logger.info("Trimmed history before \(cutoff, privacy: .public) in store \(storeID, privacy: .public)")
        }
        defaults.set(lastTrims, forKey: lastTrimsKey)
        return trimmed
    }

    @concurrent
    private static func deleteHistory(
        before cutoff: Date, inStore storeID: String, container: NSPersistentContainer
    ) async -> Bool {
        let context = container.newBackgroundContext()
        return await context.perform {
            let stores = context.persistentStoreCoordinator?.persistentStores ?? []
            guard let store = stores.first(where: { $0.identifier == storeID }) else { return false }
            let request = NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff)
            request.affectedStores = [store]
            do {
                try context.execute(request)
                return true
            } catch {
                logger.error("History trim failed: \(error.localizedDescription, privacy: .public)")
                return false
            }
        }
    }

    private struct FinishedExport: Sendable {
        let storeIdentifier: String
        let start: Date
    }

    /// Read off the notification before it reaches the main actor:
    /// `Notification` isn't Sendable.
    private nonisolated static func finishedExport(in note: Notification) -> FinishedExport? {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
              event.type == .export, event.succeeded, event.endDate != nil
        else { return nil }
        return FinishedExport(storeIdentifier: event.storeIdentifier, start: event.startDate)
    }
}
