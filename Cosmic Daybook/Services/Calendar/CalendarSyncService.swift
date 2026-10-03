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

    /// Whether EventKit access has been authorized
    var authorizationStatus: EKAuthorizationStatus = .notDetermined

    // MARK: - Change Observation
    private let storeChangeObserver = EventKitChangeObserver()

    init(context: NSManagedObjectContext? = nil, defaults: UserDefaults = .standard) {
        self.managedObjectContext = context
        self.defaults = defaults

        self.syncCalendarIdentifiers = defaults.array(forKey: UserDefaultsKeys.calendarSyncIdentifiers) as? [String] ?? []
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
