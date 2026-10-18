import Foundation

/// Students put back into the Meetings queue by hand (drag or context menu)
/// even though they met recently. Persisted in UserDefaults per device, like
/// the queue's custom order.
///
/// A requeue ends when a meeting row she didn't have when she was put back
/// appears. It used to end at a meeting dated after the requeue, but
/// `create_meeting_entry` files a meeting at midnight, which read as earlier
/// than a 10:15 requeue, so a child whose meeting was filed through Claude
/// never left Up Next (bug hunt 2026-10-17, #40).
struct MeetingQueueRequeueStore {
    private static let key = UserDefaultsKeys.meetingsWorkflowRequeuedStudents
    private static let requeuedAtKey = "at"
    private static let meetingIDsKey = "meetings"

    /// One child put back by hand.
    struct Entry: Equatable {
        /// When she was put back.
        var requeuedAt: Date
        /// The meetings she had then; a new one ends the requeue. Nil on an
        /// entry saved before 2026-10-17, which ends at a meeting dated after
        /// `requeuedAt`, as it always did.
        var meetingIDs: Set<UUID>?
    }

    private(set) var entries: [UUID: Entry] = [:]

    static func load(defaults: UserDefaults = .standard) -> MeetingQueueRequeueStore {
        var store = MeetingQueueRequeueStore()
        guard let saved = defaults.dictionary(forKey: key) else { return store }
        for (string, value) in saved {
            guard let id = UUID(uuidString: string) else { continue }
            if let date = value as? Date {
                store.entries[id] = Entry(requeuedAt: date, meetingIDs: nil)
            } else if let fields = value as? [String: Any], let date = fields[requeuedAtKey] as? Date {
                let meetings = (fields[meetingIDsKey] as? [String])?.compactMap(UUID.init(uuidString:))
                store.entries[id] = Entry(requeuedAt: date, meetingIDs: meetings.map(Set.init))
            }
        }
        return store
    }

    func save(defaults: UserDefaults = .standard) {
        var dict: [String: Any] = [:]
        for (id, entry) in entries {
            if let meetingIDs = entry.meetingIDs {
                dict[id.uuidString] = [
                    Self.requeuedAtKey: entry.requeuedAt,
                    Self.meetingIDsKey: meetingIDs.map(\.uuidString).sorted()
                ] as [String: Any]
            } else {
                dict[id.uuidString] = entry.requeuedAt
            }
        }
        defaults.set(dict, forKey: Self.key)
    }

    /// Requeues still waiting: no meeting row has appeared for the child
    /// since she was put back. `signals` are the queue's, which carry each
    /// child's meeting ids and last meeting date.
    func activeIDs(signals: [UUID: MeetingQueueSignals]) -> Set<UUID> {
        var result = Set<UUID>()
        for (id, entry) in entries where Self.isWaiting(entry, signals: signals[id]) {
            result.insert(id)
        }
        return result
    }

    /// Records a requeue with the meetings she has now, and drops entries
    /// that have already been satisfied so the store doesn't grow with every
    /// school year.
    mutating func requeue(_ id: UUID, signals: [UUID: MeetingQueueSignals], now: Date = Date()) {
        let live = activeIDs(signals: signals)
        entries = entries.filter { live.contains($0.key) }
        entries[id] = Entry(requeuedAt: now, meetingIDs: signals[id]?.meetingIDs ?? [])
    }

    private static func isWaiting(_ entry: Entry, signals: MeetingQueueSignals?) -> Bool {
        guard let had = entry.meetingIDs else {
            return (signals?.lastMet ?? .distantPast) < entry.requeuedAt
        }
        return (signals?.meetingIDs ?? []).isSubset(of: had)
    }
}
