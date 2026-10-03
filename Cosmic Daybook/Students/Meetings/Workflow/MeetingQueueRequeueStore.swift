import Foundation

/// Students put back into the Meetings queue by hand (drag or context menu)
/// even though they met recently, keyed by when they were requeued. Persisted
/// in UserDefaults per device, like the queue's custom order.
struct MeetingQueueRequeueStore {
    private static let key = UserDefaultsKeys.meetingsWorkflowRequeuedStudents

    private(set) var requeuedAt: [UUID: Date] = [:]

    static func load(defaults: UserDefaults = .standard) -> MeetingQueueRequeueStore {
        var store = MeetingQueueRequeueStore()
        guard let saved = defaults.dictionary(forKey: key) else { return store }
        for (string, value) in saved {
            if let id = UUID(uuidString: string), let date = value as? Date {
                store.requeuedAt[id] = date
            }
        }
        return store
    }

    func save(defaults: UserDefaults = .standard) {
        var dict: [String: Date] = [:]
        for (id, date) in requeuedAt {
            dict[id.uuidString] = date
        }
        defaults.set(dict, forKey: Self.key)
    }

    /// Requeues whose student hasn't completed a meeting since being put back.
    /// `lastMeetingDate` returns the most recent meeting date for a student.
    func activeIDs(lastMeetingDate: (UUID) -> Date?) -> Set<UUID> {
        var result = Set<UUID>()
        for (id, requeued) in requeuedAt {
            let met = lastMeetingDate(id) ?? .distantPast
            if met < requeued { result.insert(id) }
        }
        return result
    }

    /// Records a requeue and drops entries that have already been satisfied so
    /// the store doesn't grow with every school year.
    mutating func requeue(_ id: UUID, lastMeetingDate: (UUID) -> Date?) {
        let live = activeIDs(lastMeetingDate: lastMeetingDate)
        requeuedAt = requeuedAt.filter { live.contains($0.key) }
        requeuedAt[id] = Date()
    }
}
