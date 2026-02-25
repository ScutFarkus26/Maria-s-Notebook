import Foundation
import EventKit
import SwiftData
import OSLog

/// Service that syncs calendar events with Apple's Calendar app via EventKit.
/// Only syncs events from a specific calendar configured by the user.
@Observable
@MainActor
final class CalendarSyncService {
    private static let logger = Logger.calendar_

    static let shared = CalendarSyncService()

    private let eventStore = EKEventStore()
    var modelContext: ModelContext?

    /// The identifiers of calendars to sync from (supports multiple calendars)
    /// If empty, syncing is disabled
    var syncCalendarIdentifiers: [String] {
        didSet {
            UserDefaults.standard.set(syncCalendarIdentifiers, forKey: "CalendarSync.syncCalendarIdentifiers")
            Task { @MainActor in
                if !self.syncCalendarIdentifiers.isEmpty && self.hasFullAccess {
                    self.startObservingChanges()
                } else {
                    self.stopObservingChangesOnMainActor()
                }
            }
        }
    }

    /// The display names of calendars (for UI display only)
    var syncCalendarNames: [String] {
        didSet {
            UserDefaults.standard.set(syncCalendarNames, forKey: "CalendarSync.syncCalendarNames")
        }
    }

    /// Whether EventKit access has been authorized
    var authorizationStatus: EKAuthorizationStatus = .notDetermined

    // MARK: - Change Observation
    private var changeObserver: NSObjectProtocol?
    private var isObserving = false
    private var pendingChangeTask: Task<Void, Never>?

    init(modelContext: ModelContext? = nil) {
        self.modelContext = modelContext

        // Load calendar identifiers (with migration from legacy single-calendar storage)
        if let identifiers = UserDefaults.standard.array(forKey: "CalendarSync.syncCalendarIdentifiers") as? [String] {
            self.syncCalendarIdentifiers = identifiers
        } else if let legacyIdentifier = UserDefaults.standard.string(forKey: "CalendarSync.syncCalendarIdentifier") {
            // Migrate from legacy single calendar
            self.syncCalendarIdentifiers = [legacyIdentifier]
            UserDefaults.standard.set([legacyIdentifier], forKey: "CalendarSync.syncCalendarIdentifiers")
        } else {
            self.syncCalendarIdentifiers = []
        }

        // Load calendar names (with migration from legacy single-calendar storage)
        if let names = UserDefaults.standard.array(forKey: "CalendarSync.syncCalendarNames") as? [String] {
            self.syncCalendarNames = names
        } else if let legacyName = UserDefaults.standard.string(forKey: "CalendarSync.syncCalendarName") {
            // Migrate from legacy single calendar
            self.syncCalendarNames = [legacyName]
            UserDefaults.standard.set([legacyName], forKey: "CalendarSync.syncCalendarNames")
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
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                self.eventStore.requestFullAccessToEvents { granted, error in
                    if let error = error {
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
            let granted = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                self.eventStore.requestAccess(to: .event) { granted, error in
                    if let error = error {
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

    // MARK: - Safe Data Transfer

    /// A Sendable struct to transport data safely from the non-isolated EventKit closure
    private struct EventSyncData: Sendable {
        let title: String
        let startDate: Date
        let endDate: Date
        let location: String?
        let notes: String?
        let isAllDay: Bool
        let eventIdentifier: String
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

        do {
            try await performSync()
            lastSuccessfulSync = Date()
            lastSyncError = nil
        } catch {
            lastSyncError = error.localizedDescription
            isSyncing = false
            throw error
        }

        isSyncing = false
    }

    /// Internal sync implementation
    private func performSync() async throws {
        guard hasFullAccess else {
            throw CalendarSyncError.notAuthorized
        }

        guard let modelContext = modelContext else {
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
        let startDate = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let endDate = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()

        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: targetCalendars)
        let ekEvents = eventStore.events(matching: predicate)

        // Convert to safe data
        let syncData = ekEvents.map { event in
            EventSyncData(
                title: event.title ?? "Untitled",
                startDate: event.startDate,
                endDate: event.endDate,
                location: event.location,
                notes: event.notes,
                isAllDay: event.isAllDay,
                eventIdentifier: event.eventIdentifier
            )
        }

        // Get existing events from our database
        let existingEvents = try fetchAllCalendarEvents()
        // Use uniquingKeysWith to handle potential duplicates from CloudKit sync
        let existingByEKID = Dictionary<String, CalendarEvent>(
            existingEvents.compactMap { event -> (String, CalendarEvent)? in
                guard let ekID = event.eventKitEventID else { return nil }
                return (ekID, event)
            },
            uniquingKeysWith: { first, _ in first }
        )

        // Build a set of target calendar identifiers for quick lookup
        let targetCalendarIDs = Set(targetCalendars.map { $0.calendarIdentifier })

        // Sync each event
        for data in syncData {
            if let existing = existingByEKID[data.eventIdentifier] {
                updateCalendarEvent(existing, from: data)
            } else {
                // Find which calendar this event belongs to
                let calendarID = ekEvents.first { $0.eventIdentifier == data.eventIdentifier }?.calendar.calendarIdentifier ?? targetCalendars.first?.calendarIdentifier ?? ""
                let newEvent = createCalendarEvent(from: data, calendarID: calendarID)
                modelContext.insert(newEvent)
            }
        }

        // Delete events that no longer exist in EventKit (only for selected calendars)
        let currentEKIDs = Set(syncData.map { $0.eventIdentifier })
        for existing in existingEvents {
            if let ekID = existing.eventKitEventID,
               let calendarID = existing.eventKitCalendarID,
               !currentEKIDs.contains(ekID),
               targetCalendarIDs.contains(calendarID) {
                modelContext.delete(existing)
            }
        }

        try modelContext.save()
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

    private func fetchAllCalendarEvents() throws -> [CalendarEvent] {
        guard let modelContext = modelContext else {
            return []
        }
        let descriptor = FetchDescriptor<CalendarEvent>()
        return try modelContext.fetch(descriptor)
    }

    private func createCalendarEvent(from data: EventSyncData, calendarID: String) -> CalendarEvent {
        CalendarEvent(
            title: data.title,
            startDate: data.startDate,
            endDate: data.endDate,
            location: data.location,
            notes: data.notes,
            isAllDay: data.isAllDay,
            eventKitEventID: data.eventIdentifier,
            eventKitCalendarID: calendarID,
            lastSyncedAt: Date()
        )
    }

    private func updateCalendarEvent(_ event: CalendarEvent, from data: EventSyncData) {
        event.title = data.title
        event.startDate = data.startDate
        event.endDate = data.endDate
        event.location = data.location
        event.notes = data.notes
        event.isAllDay = data.isAllDay
        event.lastSyncedAt = Date()
    }

    // MARK: - Automatic Syncing

    private func startObservingChanges() {
        guard !isObserving else { return }
        guard hasFullAccess else { return }
        guard !syncCalendarIdentifiers.isEmpty else { return }

        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                // Cancel any pending task to prevent accumulation
                self.pendingChangeTask?.cancel()
                self.pendingChangeTask = Task { @MainActor [weak self] in
                    await self?.handleEventStoreChanged()
                }
            }
        }

        isObserving = true
    }

    @MainActor
    private func stopObservingChangesOnMainActor() {
        pendingChangeTask?.cancel()
        pendingChangeTask = nil
        if let observer = changeObserver {
            NotificationCenter.default.removeObserver(observer)
            changeObserver = nil
        }
        isObserving = false
    }

    private nonisolated func stopObservingChanges() {
        Task { @MainActor [weak self] in
            self?.stopObservingChangesOnMainActor()
        }
    }

    private func handleEventStoreChanged() async {
        guard !syncCalendarIdentifiers.isEmpty else { return }
        guard hasFullAccess else { return }
        guard modelContext != nil else { return }

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
