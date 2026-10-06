import Foundation

/// The store a kind of row lives in, so a grace knows whose imports from iCloud count.
nonisolated enum ImportStoreKind: Sendable {
    /// `private.sqlite`: the guide's own rows, students and work included.
    case privateStore
    /// `shared.sqlite`: the classroom share on a notebook that joined someone else's.
    case sharedStore

    /// The store's configuration in the model (`CoreDataStack.privateConfiguration`, `.sharedConfiguration`).
    var configurationName: String {
        switch self {
        case .privateStore: return CoreDataStack.privateConfiguration
        case .sharedStore: return CoreDataStack.sharedConfiguration
        }
    }
}

/// How long a row must stay missing before a launch cleanup acts on the rows that name it.
///
/// A work row or lesson that names a student with no student row is usually a child deleted
/// long ago. But a student can also be missing for a moment: when `ClassroomShareRelease`
/// takes her out of the classroom share, another device can receive the delete of the shared
/// row before the private copy that replaces it, and a launch in between would clear her from
/// every work and lesson — and sync that. A check-in whose work row is missing is the same
/// question (2026-10-05): the work may simply not have arrived yet. So an id is only acted on
/// once it has been missing on passes at least `interval` apart **and** the store that holds
/// that kind of row has finished an import from iCloud since it was first seen missing
/// (`lastImport`): a device asleep or offline for that day has heard nothing new. With no
/// import known, the id keeps waiting. An id that turns up again is forgotten.
///
/// Named for its first use; each `Kind` keeps its own ledger, per device and store environment
/// (cleared by Reset Local Cache), carried in and out of the launch pass as a plain
/// dictionary: id → when it was first seen missing. Ids are compared trimmed and upper-cased,
/// as `UUID.uuidString` writes them (`normalizedID`).
nonisolated final class OrphanStudentGrace {
    /// What kind of row is missing.
    nonisolated enum Kind: Sendable {
        /// Students that work rows and lessons name.
        case student
        /// Work rows that check-ins name.
        case checkInWork

        var defaultsKey: String {
            switch self {
            case .student: return UserDefaultsKeys.orphanStudentGrace
            case .checkInWork: return UserDefaultsKeys.orphanCheckInGrace
            }
        }
    }

    static let interval: TimeInterval = 24 * 60 * 60
    /// Ids missing this long have long since been cleaned; forget them so the ledger stays small.
    static let forgetAfter: TimeInterval = 60 * 24 * 60 * 60

    private(set) var ledger: [String: Date]
    let now: Date
    let interval: TimeInterval
    /// When the store holding the missing kind of row last finished an import, or nil when
    /// none is known.
    let lastImport: Date?

    init(
        ledger: [String: Date],
        now: Date = Date(),
        interval: TimeInterval = OrphanStudentGrace.interval,
        lastImport: Date? = nil
    ) {
        // A ledger written before ids were normalized keeps each id's earliest sighting.
        var normalized: [String: Date] = [:]
        for (id, firstSeen) in ledger {
            let key = Self.normalizedID(id)
            normalized[key] = min(normalized[key] ?? firstSeen, firstSeen)
        }
        self.ledger = normalized
        self.now = now
        self.interval = interval
        self.lastImport = lastImport
    }

    /// Of `missing` (normalized ids some row names that no row of the kind has), the ones
    /// missing long enough, with an import since, to act on. Records the rest as first seen
    /// now; forgets ids in `validIDs` (here again) and ids missing past `forgetAfter`.
    func admit(missing: Set<String>, validIDs: Set<String>) -> Set<String> {
        ledger = ledger.filter { !validIDs.contains($0.key) && now.timeIntervalSince($0.value) < Self.forgetAfter }
        var ready = Set<String>()
        for id in missing {
            guard let firstSeen = ledger[id] else {
                ledger[id] = now
                continue
            }
            let waitedLongEnough = now.timeIntervalSince(firstSeen) >= interval
            let importedSince = lastImport.map { $0 > firstSeen } ?? false
            if waitedLongEnough && importedSince { ready.insert(id) }
        }
        return ready
    }

    /// The form ids are compared in: trimmed and upper-cased, as `UUID.uuidString` writes them.
    /// A `studentID` or `workID` written by hand or by an older path may be lower-cased.
    static func normalizedID(_ id: String) -> String {
        id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    // MARK: - Persistence

    static func load(from defaults: UserDefaults, kind: Kind = .student) -> [String: Date] {
        let raw = defaults.dictionary(forKey: kind.defaultsKey) as? [String: Double] ?? [:]
        return raw.mapValues { Date(timeIntervalSinceReferenceDate: $0) }
    }

    static func save(_ ledger: [String: Date], to defaults: UserDefaults, kind: Kind = .student) {
        defaults.set(ledger.mapValues(\.timeIntervalSinceReferenceDate), forKey: kind.defaultsKey)
    }
}
