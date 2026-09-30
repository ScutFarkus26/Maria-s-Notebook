import Foundation

/// How long a student id must stay missing before the launch cleanups strip it from work and
/// lessons.
///
/// A work row or lesson that names a student with no student row is usually a child deleted
/// long ago. But a student can also be missing for a moment: when `ClassroomShareRelease`
/// takes her out of the classroom share, another device can receive the delete of the shared
/// row before the private copy that replaces it, and a launch in between would clear her from
/// every work and lesson — and sync that. So an id is only acted on once it has been missing
/// on passes at least `interval` apart; an id that turns up again is forgotten.
///
/// One ledger per device and store environment (`UserDefaultsKeys.orphanStudentGrace`,
/// cleared by Reset Local Cache), carried in and out of the launch pass as a plain
/// dictionary: id → when it was first seen missing.
nonisolated final class OrphanStudentGrace {
    static let interval: TimeInterval = 24 * 60 * 60
    /// Ids missing this long have long since been cleaned; forget them so the ledger stays small.
    static let forgetAfter: TimeInterval = 60 * 24 * 60 * 60

    private(set) var ledger: [String: Date]
    let now: Date
    let interval: TimeInterval

    init(ledger: [String: Date], now: Date = Date(), interval: TimeInterval = OrphanStudentGrace.interval) {
        self.ledger = ledger
        self.now = now
        self.interval = interval
    }

    /// Of `missing` (ids some row names that no student has), the ones missing long enough to
    /// act on. Records the rest as first seen now; forgets ids that are students again.
    func admit(missing: Set<String>, validIDs: Set<String>) -> Set<String> {
        ledger = ledger.filter { !validIDs.contains($0.key) && now.timeIntervalSince($0.value) < Self.forgetAfter }
        var ready = Set<String>()
        for id in missing {
            if let first = ledger[id] {
                if now.timeIntervalSince(first) >= interval { ready.insert(id) }
            } else {
                ledger[id] = now
            }
        }
        return ready
    }

    // MARK: - Persistence

    static func load(from defaults: UserDefaults) -> [String: Date] {
        let raw = defaults.dictionary(forKey: UserDefaultsKeys.orphanStudentGrace) as? [String: Double] ?? [:]
        return raw.mapValues { Date(timeIntervalSinceReferenceDate: $0) }
    }

    static func save(_ ledger: [String: Date], to defaults: UserDefaults) {
        defaults.set(ledger.mapValues(\.timeIntervalSinceReferenceDate), forKey: UserDefaultsKeys.orphanStudentGrace)
    }
}
