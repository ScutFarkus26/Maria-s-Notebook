import Foundation
import CoreData
import EventKit
import OSLog

/// Sendable DTO carrying one EventKit event out of `EKEvent` into the mirror.
nonisolated struct CalendarEventSyncData: Sendable, Equatable {
    let title: String
    let startDate: Date
    let endDate: Date
    let location: String?
    let notes: String?
    let isAllDay: Bool
    let eventIdentifier: String
    /// The event's calendar. A new row takes its first occurrence's.
    let calendarIdentifier: String?
}

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

    private let eventStore = EKEventStore()
    var managedObjectContext: NSManagedObjectContext?

    /// The identifiers of calendars to sync from (supports multiple calendars)
    /// If empty, syncing is disabled
    var syncCalendarIdentifiers: [String] {
        didSet {
            UserDefaults.standard.set(syncCalendarIdentifiers, forKey: UserDefaultsKeys.calendarSyncIdentifiers)
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
            UserDefaults.standard.set(syncCalendarNames, forKey: UserDefaultsKeys.calendarSyncNames)
        }
    }

    /// Whether EventKit access has been authorized
    var authorizationStatus: EKAuthorizationStatus = .notDetermined

    // MARK: - Change Observation
    private let storeChangeObserver = EventKitChangeObserver()

    init(context: NSManagedObjectContext? = nil) {
        self.managedObjectContext = context

        // Load calendar identifiers (with migration from legacy single-calendar storage)
        let defaults = UserDefaults.standard
        if let identifiers = defaults.array(forKey: UserDefaultsKeys.calendarSyncIdentifiers) as? [String] {
            self.syncCalendarIdentifiers = identifiers
        } else if let legacyIdentifier = defaults.string(forKey: UserDefaultsKeys.calendarSyncLegacyIdentifier) {
            // Migrate from legacy single calendar
            self.syncCalendarIdentifiers = [legacyIdentifier]
            UserDefaults.standard.set([legacyIdentifier], forKey: UserDefaultsKeys.calendarSyncIdentifiers)
        } else {
            self.syncCalendarIdentifiers = []
        }

        // Load calendar names (with migration from legacy single-calendar storage)
        if let names = UserDefaults.standard.array(forKey: UserDefaultsKeys.calendarSyncNames) as? [String] {
            self.syncCalendarNames = names
        } else if let legacyName = UserDefaults.standard.string(forKey: UserDefaultsKeys.calendarSyncLegacyName) {
            // Migrate from legacy single calendar
            self.syncCalendarNames = [legacyName]
            UserDefaults.standard.set([legacyName], forKey: UserDefaultsKeys.calendarSyncNames)
        } else {
            self.syncCalendarNames = []
        }

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
        if #available(macOS 14.0, iOS 17.0, *) {
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
        } else {
            // swiftlint:disable closure_parameter_position
            let granted = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Bool, Error>) in
                // swiftlint:enable closure_parameter_position
                self.eventStore.requestAccess(to: .event) { granted, error in
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
    }

    /// Check if we have full access to calendars
    private var hasFullAccess: Bool {
        if #available(macOS 14.0, iOS 17.0, *) {
            return authorizationStatus == .fullAccess
        } else {
            return authorizationStatus == .authorized
        }
    }

    /// Sync calendar events from the configured calendar
    /// - Parameter force: If true, bypasses the throttle interval
    func syncEvents(force: Bool = false) async throws {
        // Throttle: Skip if called too soon (within 10 minutes of last sync)
        let throttleInterval: TimeInterval = 10 * 60
        if !force, let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) < throttleInterval {
            return
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
            lastSyncError = error.localizedDescription
            SyncEventLogger.shared.log("calendar", status: "error", message: error.localizedDescription)
            isSyncing = false
            throw error
        }

        isSyncing = false
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

        // Find all target calendars
        let targetCalendars = syncCalendarIdentifiers.compactMap { findCalendar(byIdentifier: $0) }
        guard !targetCalendars.isEmpty else {
            throw CalendarSyncError.calendarNotFound(syncCalendarNames.joined(separator: ", "))
        }

        // Fetch events for a window around today (7 days back, 30 days forward)
        let startDate = AppCalendar.shared.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let endDate = AppCalendar.shared.date(byAdding: .day, value: 30, to: Date()) ?? Date()

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: targetCalendars)
        let ekEvents = eventStore.events(matching: predicate)

        // Convert to safe data
        let syncData = ekEvents.map { event in
            CalendarEventSyncData(
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                notes: event.notes,
                isAllDay: event.isAllDay,
                eventIdentifier: event.eventIdentifier,
                calendarIdentifier: event.calendar?.calendarIdentifier
            )
        }

        // Insert new events, rewrite only the rows whose values changed, and
        // delete the ones gone from the fetched window. An unchanged calendar
        // leaves the context clean, so the save below writes nothing.
        let fetch = EventKitMirror.CalendarFetch(
            calendarIDs: Set(targetCalendars.map(\.calendarIdentifier)),
            fallbackCalendarID: targetCalendars.first?.calendarIdentifier ?? "",
            windowStart: startDate,
            windowEnd: endDate
        )
        EventKitMirror.reconcileEvents(syncData, from: fetch, in: context, now: Date())

        context.safeSave()
        lastSyncTime = Date()
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

    // MARK: - Private Helpers

    private func findCalendar(byIdentifier identifier: String) -> EKCalendar? {
        let calendars = eventStore.calendars(for: .event)
        return calendars.first { $0.calendarIdentifier == identifier }
    }

    // MARK: - Automatic Syncing

    private func startObservingChanges() {
        guard hasFullAccess else { return }
        guard !syncCalendarIdentifiers.isEmpty else { return }

        storeChangeObserver.start(eventStore: eventStore) { [weak self] in
            await self?.handleEventStoreChanged()
        }
    }

    private nonisolated func stopObservingChanges() {
        Task { @MainActor [weak self] in
            self?.storeChangeObserver.stop()
        }
    }

    private func handleEventStoreChanged() async {
        guard !syncCalendarIdentifiers.isEmpty else { return }
        guard hasFullAccess else { return }
        guard managedObjectContext != nil else { return }

        // Debounce: Only sync if we haven't synced recently (within last 30 seconds)
        if let lastSync = lastSyncTime, Date().timeIntervalSince(lastSync) < 30.0 {
            return
        }

        do {
            try await syncEvents()
            lastSyncTime = Date()
        } catch {
            Self.logger.warning("Automatic sync failed: \(error.localizedDescription)")
        }
    }

    private var lastSyncTime: Date?

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

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Calendar access has not been granted. Please authorize access in Settings."
        case .noCalendarConfigured:
            return "No calendar has been configured for syncing."
        case .calendarNotFound(let name):
            return "Calendar '\(name)' not found. Please check the calendar selection in settings."
        case .modelContextUnavailable:
            return "Database context is not available. Please try again."
        }
    }
}
