import Foundation
import CoreData
import EventKit
import OSLog

/// Service that syncs calendar events with Apple's Calendar app via EventKit.
/// Only syncs events from a specific calendar configured by the user.
@Observable
final class CalendarSyncService {
    private static let logger = Logger.calendar_

    /// The process-wide instance: the one `EKEventStore` observer and the
    /// sync state the Today card watches. App code reaches it through
    /// `AppDependencies.calendarSync`, which also binds `managedObjectContext`
    /// to the active store; only the dependency container names `.shared`.
    static let shared = CalendarSyncService()

    /// Created on first use, not with the service: Apple calls an event store
    /// slow to set up, and with no calendar chosen nothing here needs one.
    @ObservationIgnored private lazy var eventStore = EKEventStore()
    var managedObjectContext: NSManagedObjectContext?

    /// Where the calendar choice is kept; tests pass their own suite.
    private let defaults: UserDefaults

    /// The identifiers of calendars to sync from (supports multiple calendars)
    /// If empty, syncing is disabled
    var syncCalendarIdentifiers: [String] {
        didSet {
            defaults.set(syncCalendarIdentifiers, forKey: UserDefaultsKeys.calendarSyncIdentifiers)
            Task {
                if !self.syncCalendarIdentifiers.isEmpty && self.hasFullAccess {
                    self.startObservingChanges()
                } else {
                    self.storeChangeObserver.stop()
                }
            }
        }
    }

    /// The display names of calendars (for UI display only)
    var syncCalendarNames: [String] {
        didSet {
            defaults.set(syncCalendarNames, forKey: UserDefaultsKeys.calendarSyncNames)
        }
    }

    /// Where this device keeps the keys (`EventKitMirror.calendarKey`) each
    /// chosen calendar has had, by its local identifier, newest last. A key
    /// is the calendar's title, so a rename changes it; the old key lets this
    /// device keep moving and deleting the rows it filed under it, and remove
    /// them when the calendar is turned off. Kept on this device only, like
    /// the choice of calendars.
    static let calendarKeysDefaultsKey = "CalendarSync.calendarKeysByIdentifier"

    /// How many keys are kept per calendar.
    private static let rememberedKeysPerCalendar = 5

    private var rememberedCalendarKeys: [String: [String]] {
        get { defaults.dictionary(forKey: Self.calendarKeysDefaultsKey) as? [String: [String]] ?? [:] }
        set { defaults.set(newValue, forKey: Self.calendarKeysDefaultsKey) }
    }

    /// Whether EventKit access has been authorized
    var authorizationStatus: EKAuthorizationStatus = .notDetermined

    // MARK: - Change Observation
    private let storeChangeObserver = EventKitChangeObserver()

    init(context: NSManagedObjectContext? = nil, defaults: UserDefaults = .standard) {
        self.managedObjectContext = context
        self.defaults = defaults

        self.syncCalendarIdentifiers =
            defaults.array(forKey: UserDefaultsKeys.calendarSyncIdentifiers) as? [String] ?? []
        self.syncCalendarNames = defaults.array(forKey: UserDefaultsKeys.calendarSyncNames) as? [String] ?? []

        self.authorizationStatus = EKEventStore.authorizationStatus(for: .event)

        // Start observing if we have access and sync calendars configured
        if !syncCalendarIdentifiers.isEmpty && hasFullAccess {
            startObservingChanges()
        }
    }

    deinit {
        stopObservingChanges()
    }

    /// Request access to Calendar
    func requestAuthorization() async throws -> Bool {
        // swiftlint:disable closure_parameter_position
        let granted = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Bool, Error>) in
            // swiftlint:enable closure_parameter_position
            self.eventStore.requestFullAccessToEvents { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: granted)
                }
            }
        }

        // Update status and start observing on main actor
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
        if granted && !syncCalendarIdentifiers.isEmpty {
            startObservingChanges()
        }

        return granted
    }

    /// Check if we have full access to calendars
    private var hasFullAccess: Bool {
        authorizationStatus == .fullAccess
    }

    /// Sync calendar events from the configured calendar
    /// - Parameter force: If true, bypasses the throttle interval
    /// - Returns: false when the throttle skipped the call, true when a sync ran.
    @discardableResult
    func syncEvents(force: Bool = false) async throws -> Bool {
        // Throttle: Skip if called too soon (within 10 minutes of last sync)
        let throttleInterval: TimeInterval = 10 * 60
        if !force, let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) < throttleInterval {
            return false
        }

        isSyncing = true
        lastSyncError = nil
        SyncEventLogger.shared.log("calendar", status: "started", message: "Calendar sync started")

        do {
            try await performSync()
            lastSuccessfulSync = Date()
            lastSyncError = nil
            SyncEventLogger.shared.log("calendar", status: "success", message: "Calendar sync completed")
        } catch {
            // Plain words for Today's header; the raw text for Sync History's Details.
            lastSyncError = AppErrorMessages.syncMessage(for: error, service: "Calendar")
            let nsError = error as NSError
            SyncEventLogger.shared.log(
                "calendar", status: "error", message: "Couldn't sync with Calendar",
                detail: "\(nsError.localizedDescription) [\(nsError.domain) (\(nsError.code))]"
            )
            isSyncing = false
            throw error
        }

        isSyncing = false
        return true
    }

    private func performSync() async throws {
        guard hasFullAccess else {
            throw CalendarSyncError.notAuthorized
        }

        guard let context = managedObjectContext else {
            throw CalendarSyncError.modelContextUnavailable
        }

        guard !syncCalendarIdentifiers.isEmpty else {
            throw CalendarSyncError.noCalendarConfigured
        }

        // Find all target calendars, from one walk of the calendars (it was one per identifier)
        let calendars = eventStore.calendars(for: .event)
        let targetCalendars = syncCalendarIdentifiers.compactMap { identifier in
            calendars.first { $0.calendarIdentifier == identifier }
        }
        guard !targetCalendars.isEmpty else {
            throw CalendarSyncError.calendarNotFound(syncCalendarNames.joined(separator: ", "))
        }

        // Fetch events for a window around today (7 days back, 30 days forward)
        let startDate = AppCalendar.shared.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let endDate = AppCalendar.shared.date(byAdding: .day, value: 30, to: Date()) ?? Date()

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: targetCalendars)
        let ekEvents = eventStore.events(matching: predicate)

        let syncData = ekEvents.map(Self.syncData(for:))

        // Insert new occurrences, rewrite only the rows whose values changed,
        // and delete the ones gone from this device's calendars inside the
        // fetched window. An unchanged calendar leaves the context clean, so
        // the save below writes nothing.
        var keysByIdentifier: [String: String] = [:]
        for calendar in targetCalendars {
            keysByIdentifier[calendar.calendarIdentifier] = Self.calendarKey(for: calendar)
        }
        let currentKeys = Set(keysByIdentifier.values)
        let remembered = rememberedCalendarKeys
        let fetch = EventKitMirror.CalendarFetch(
            calendarKeys: currentKeys,
            formerCalendarKeys: Set(keysByIdentifier.keys.flatMap { remembered[$0] ?? [] }).subtracting(currentKeys),
            unsyncedCalendarKeys: Set(calendars.map(Self.calendarKey(for:))).subtracting(currentKeys),
            localCalendarIDs: Set(keysByIdentifier.keys),
            fallbackCalendarKey: targetCalendars.first.map(Self.calendarKey(for:)) ?? "",
            windowStart: startDate,
            windowEnd: endDate
        )
        EventKitMirror.reconcileEvents(syncData, from: fetch, in: context, now: Date())

        if context.safeSave() {
            remember(keysByIdentifier)
        }
        lastSyncTime = Date()
    }

    /// Notes the key each synced calendar had this time, after older ones.
    private func remember(_ keysByIdentifier: [String: String]) {
        var remembered = rememberedCalendarKeys
        for (identifier, key) in keysByIdentifier where remembered[identifier]?.last != key {
            let keys = (remembered[identifier] ?? []).filter { $0 != key } + [key]
            remembered[identifier] = Array(keys.suffix(Self.rememberedKeysPerCalendar))
        }
        if remembered != rememberedCalendarKeys {
            rememberedCalendarKeys = remembered
        }
    }

    // MARK: - Choosing calendars

    /// Changes which calendars this device syncs. A calendar turned off has
    /// its rows removed from the notebook at once, whatever their dates; if
    /// another device still syncs it, that device's next sync brings its
    /// window back. The choice itself stays on this device.
    func updateSelection(identifiers: [String], names: [String]) {
        let dropped = Set(syncCalendarIdentifiers).subtracting(identifiers)
        syncCalendarIdentifiers = identifiers
        syncCalendarNames = names
        guard !dropped.isEmpty, let context = managedObjectContext else { return }

        let remembered = rememberedCalendarKeys
        let live = hasFullAccess ? liveCalendarKeys() : [:]
        func keys(of identifiers: some Sequence<String>) -> Set<String> {
            identifiers.reduce(into: Set<String>()) { keys, identifier in
                keys.formUnion(remembered[identifier] ?? [])
                if let key = live[identifier] { keys.insert(key) }
            }
        }
        // A key a calendar still chosen also has stays (two calendars can
        // share an account and a title).
        let removedKeys = keys(of: dropped).subtracting(keys(of: identifiers))
        rememberedCalendarKeys = remembered.filter { !dropped.contains($0.key) }

        let removed = EventKitMirror.removeEvents(inCalendars: removedKeys, in: context)
        if removed > 0 {
            context.safeSave()
        }
    }

    /// Every calendar's key on this device, by local identifier.
    private func liveCalendarKeys() -> [String: String] {
        var keys: [String: String] = [:]
        for calendar in eventStore.calendars(for: .event) {
            keys[calendar.calendarIdentifier] = Self.calendarKey(for: calendar)
        }
        return keys
    }

    /// Represents a calendar with both identifier and display name
    struct CalendarInfo: Identifiable, Hashable, Sendable {
        let identifier: String
        let name: String
        let color: CGColor?
        var id: String { identifier }

        nonisolated static func == (lhs: CalendarInfo, rhs: CalendarInfo) -> Bool {
            lhs.identifier == rhs.identifier && lhs.name == rhs.name
        }

        nonisolated func hash(into hasher: inout Hasher) {
            hasher.combine(identifier)
            hasher.combine(name)
        }
    }

    /// Get all available calendars with their identifiers
    func getAvailableCalendarsWithIdentifiers() -> [CalendarInfo] {
        guard hasFullAccess else {
            return []
        }

        let calendars = eventStore.calendars(for: .event)
        return calendars.map { CalendarInfo(identifier: $0.calendarIdentifier, name: $0.title, color: $0.cgColor) }
    }

    // MARK: - Automatic Syncing

    private func startObservingChanges() {
        guard hasFullAccess else { return }
        guard !syncCalendarIdentifiers.isEmpty else { return }

        storeChangeObserver.start(observing: eventStore) { [weak self] in
            await self?.handleEventStoreChanged()
        }
    }

    private nonisolated func stopObservingChanges() {
        Task { @MainActor [weak self] in
            self?.storeChangeObserver.stop()
        }
    }

    /// Runs a sync after the store has gone quiet (`EventKitChangeObserver`).
    func handleEventStoreChanged() async {
        guard !syncCalendarIdentifiers.isEmpty else { return }
        guard hasFullAccess else { return }
        guard managedObjectContext != nil else { return }

        // `syncEvents` skips a call within 10 minutes of the last sync, so the
        // time is recorded only when a sync ran. Recording it after a skipped
        // one (as this did, behind a 30-second check the throttle covers)
        // pushed the next sync back on every change: while the calendar kept
        // changing at least every 10 minutes, no unforced sync ran at all.
        do {
            if try await syncEvents() {
                lastSyncTime = Date()
            }
        } catch {
            Self.logger.warning("Automatic sync failed: \(error.localizedDescription)")
        }
    }

    /// When the last sync ran; the 10-minute throttle reads it.
    var lastSyncTime: Date?

    /// Sync status for UI visibility
    var lastSuccessfulSync: Date?
    var lastSyncError: String?
    var isSyncing: Bool = false
}

enum CalendarSyncError: LocalizedError, Equatable {
    case notAuthorized
    case noCalendarConfigured
    case calendarNotFound(String)
    case modelContextUnavailable

    /// Shown as is (Today's header, the Calendar settings), so plain words.
    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Cosmic Daybook doesn't have access to Calendar. "
                + "Turn it on in \(SystemSettingsApp.privacyPath("Calendars"))."
        case .noCalendarConfigured:
            return "Choose a calendar to sync first."
        case .calendarNotFound(let name):
            let which = name.isEmpty ? "the calendars you chose" : "\u{201C}\(name)\u{201D}"
            return "Couldn't find \(which). It may have been renamed or deleted. Choose your calendars again."
        case .modelContextUnavailable:
            return "Couldn't reach your notebook to sync. Try again."
        }
    }
}
