import Foundation
import OSLog

// MARK: - Sync Event Logger

/// Logs sync events (iCloud, Calendar, Reminders) for display in the sync history view.
/// Events are stored in UserDefaults as JSON, capped at 50 entries.
@Observable @MainActor
final class SyncEventLogger {
    private static let logger = Logger.sync
    static let shared = SyncEventLogger()

    struct SyncEvent: Codable, Identifiable, Sendable {
        let id: UUID
        let timestamp: Date
        let type: String      // "cloudkit", "calendar", "reminders"
        let status: String    // "success", "error", "started"
        let message: String
    }

    private let maxEvents = 50
    private let storageKey = "SyncHistory.events"

    private(set) var events: [SyncEvent] = []

    init() {
        loadEvents()
    }

    func log(_ type: String, status: String, message: String) {
        let event = SyncEvent(
            id: UUID(),
            timestamp: Date(),
            type: type,
            status: status,
            message: message
        )
        events.insert(event, at: 0)
        if events.count > maxEvents {
            events = Array(events.prefix(maxEvents))
        }
        saveEvents()
    }

    func clearHistory() {
        events = []
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    // MARK: - Persistence

    private func loadEvents() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            events = try JSONDecoder().decode([SyncEvent].self, from: data)
        } catch {
            Self.logger.warning("Failed to decode sync events: \(error.localizedDescription)")
        }
    }

    private func saveEvents() {
        do {
            let data = try JSONEncoder().encode(events)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            Self.logger.warning("Failed to encode sync events: \(error.localizedDescription)")
        }
    }
}
