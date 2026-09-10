import Foundation

// MARK: - Sync Event Logger

/// Logs sync events (iCloud, Calendar, Reminders) for display in the sync history view.
/// Events are stored in UserDefaults as JSON, capped at 50 entries.
///
/// Two things keep this off the hot path. A repeat of the most recent event —
/// same type, status, and message — inside `coalesceWindow` bumps that event's
/// count and timestamp instead of adding a row: CloudKit reports "Remote
/// changes received" once per imported batch, which is dozens of times a
/// second during an import. And the JSON write to UserDefaults is debounced,
/// so a burst costs one encode rather than one per event.
@Observable
final class SyncEventLogger {
    static let shared = SyncEventLogger()

    struct SyncEvent: Codable, Identifiable, Sendable {
        let id: UUID
        /// The most recent occurrence.
        var timestamp: Date
        let type: String      // "cloudkit", "calendar", "reminders"
        let status: String    // "success", "error", "started"
        let message: String
        /// How many times this event repeated inside the coalesce window.
        var count: Int

        init(
            id: UUID = UUID(),
            timestamp: Date,
            type: String,
            status: String,
            message: String,
            count: Int = 1
        ) {
            self.id = id
            self.timestamp = timestamp
            self.type = type
            self.status = status
            self.message = message
            self.count = count
        }

        /// Rows written before `count` existed decode as a single occurrence.
        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: SyncEventCodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            timestamp = try container.decode(Date.self, forKey: .timestamp)
            type = try container.decode(String.self, forKey: .type)
            status = try container.decode(String.self, forKey: .status)
            message = try container.decode(String.self, forKey: .message)
            count = try container.decodeIfPresent(Int.self, forKey: .count) ?? 1
        }
    }

    private let maxEvents = 50
    private let defaults: UserDefaults
    private let storageKey: String

    /// A repeat of the latest event inside this window folds into it.
    let coalesceWindow: TimeInterval

    /// Quiet period after the last change before the list is written out.
    let saveDelay: Duration

    /// Injectable clock so tests can step past the coalesce window.
    var now: () -> Date = { Date() }

    private(set) var events: [SyncEvent] = []
    private var saveTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "SyncHistory.events",
        coalesceWindow: TimeInterval = 30,
        saveDelay: Duration = .seconds(1)
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
        self.coalesceWindow = coalesceWindow
        self.saveDelay = saveDelay
        loadEvents()
    }

    func log(_ type: String, status: String, message: String) {
        let stamp = now()
        if let latest = events.first,
           latest.type == type, latest.status == status, latest.message == message,
           stamp.timeIntervalSince(latest.timestamp) < coalesceWindow {
            events[0].timestamp = stamp
            events[0].count += 1
        } else {
            let event = SyncEvent(timestamp: stamp, type: type, status: status, message: message)
            events.insert(event, at: 0)
            if events.count > maxEvents {
                events = Array(events.prefix(maxEvents))
            }
        }
        scheduleSave()
    }

    func clearHistory() {
        saveTask?.cancel()
        saveTask = nil
        events = []
        defaults.removeObject(forKey: storageKey)
    }

    /// Writes any pending change now instead of after `saveDelay`.
    func flushPendingSave() {
        saveTask?.cancel()
        saveTask = nil
        saveEvents()
    }

    // MARK: - Persistence

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.saveDelay)
            } catch {
                return // superseded by a newer change
            }
            self.saveEvents()
        }
    }

    private func loadEvents() {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([SyncEvent].self, from: data) else {
            return
        }
        events = decoded
    }

    private func saveEvents() {
        guard let data = try? JSONEncoder().encode(events) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

/// Kept outside `SyncEvent` only to satisfy the one-level nesting rule.
private enum SyncEventCodingKeys: String, CodingKey {
    case id, timestamp, type, status, message, count
}
