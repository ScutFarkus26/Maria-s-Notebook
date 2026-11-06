import Foundation

// What `ParentLockerSync` runs: one run, for the whole class or some
// children, and a whole-class send owed until it can go. And what stands
// between runs: today's Close Arrival & Send runs under way, and the lines
// a run leaves on the ParentLocker line until one shows them fixed.

/// One run of the sync: the whole class or some children, for a day.
nonisolated struct ParentLockerJob: Sendable, Equatable {
    /// `.deadline` is the guide's check after the day's due time.
    enum Reason: Sendable, Equatable { case live, closeArrival, backstop, deadline, owed, sendNow, request }
    var day: Date
    /// Nil for the whole class.
    var children: Set<UUID>?
    var reason: Reason
    var preview = false
    /// Retries already made.
    var attempt = 0
    /// Of `children`, those whose change synced in from another device, and
    /// what this device had seen of them in ParentLocker when it arrived, or
    /// with nothing seen, their mark here from before the change.
    var imported: Set<UUID> = []
    var importedBaseline: [UUID: ParentLockerSeen] = [:]
    var importedBefore: [UUID: ParentLockerPlanner.DayMark?] = [:]
    /// For a whole-class send: the changes synced in, or made before
    /// "after", it covers once it reaches ParentLocker.
    var settles: Set<UUID> = []

    var isWholeClass: Bool { children == nil }

    /// This live retry taking the place of `pending`, an earlier one: both's
    /// children go, each change synced in with what this device had seen of
    /// it, unless this one carries a newer change of the device's own for
    /// the child (review of the 2026-11-05 fixes, E10).
    func merging(_ pending: ParentLockerJob) -> ParentLockerJob {
        var merged = self
        let own = (children ?? []).subtracting(imported)
        merged.children = (children ?? []).union(pending.children ?? [])
        merged.imported = imported.union(pending.imported.subtracting(own))
        let kept = merged.imported
        merged.importedBaseline = pending.importedBaseline.merging(importedBaseline) { $1 }
            .filter { kept.contains($0.key) }
        merged.importedBefore = pending.importedBefore.merging(importedBefore) { $1 }
            .filter { kept.contains($0.key) }
        return merged
    }

    /// Goes only over what this device last saw of each child in
    /// ParentLocker, leaving one saved since to the device that saved it: the
    /// guide's backstops, a whole-class retry and a whole-class send owed
    /// from before, which may come from a device that hasn't caught up (bug
    /// hunt 2026-10-13 afternoon, H5).
    var comparesWithLastSeen: Bool {
        switch reason {
        case .backstop, .deadline, .owed: true
        default: isWholeClass && attempt > 0
        }
    }
}

/// A whole-class send owed: why, and when it goes (nil: owed, waiting for the
/// next change, a return to the app, a sign-in or Send Now).
nonisolated struct ParentLockerWholeClass: Sendable, Equatable {
    /// `.sendNow`: Send Now (or MCP's send) owed: made while this device
    /// needed a sign-in, or failed. Like Send Now, it doesn't record a day
    /// with children unmarked (review of the 2026-11-05 fixes, E4). The raw
    /// values are kept with what's owed across launches (`ParentLockerUnsent.reason`).
    enum Reason: String, Sendable, Equatable { case closeArrival, backstop, owed, sendNow }
    var reason: Reason
    var due: Date?
    /// Tries already made: a send that failed, or one owed from before
    /// launch, goes as a retry (`ParentLockerJob.comparesWithLastSeen`).
    var attempt = 0

    init(reason: Reason, due: Date?, attempt: Int = 0) {
        self.reason = reason
        self.due = due
        self.attempt = attempt
    }

    /// A failed whole-class `job`, owed until it can go again, as itself:
    /// Close Arrival & Send's stays one, so its Undo can still take it back
    /// (bug hunt 2026-10-13 afternoon, H2), and Send Now's (or MCP's) one,
    /// so a day with children unmarked still isn't recorded (review of the
    /// 2026-11-05 fixes, E4); any other is a send owed.
    init(retrying job: ParentLockerJob) {
        let reason: Reason = switch job.reason {
        case .closeArrival: .closeArrival
        case .sendNow, .request: .sendNow
        default: .owed
        }
        self.init(reason: reason, due: nil, attempt: 1)
    }

    /// The run it makes.
    var jobReason: ParentLockerJob.Reason {
        switch reason {
        case .closeArrival: .closeArrival
        case .backstop: .backstop
        case .owed: .owed
        case .sendNow: .sendNow
        }
    }
}

/// A row a save sent for a child in one class, kept until the save's reply
/// says it landed: a save whose reply was lost may still have reached
/// ParentLocker, and a later run that finds it there knows it for this
/// device's own (bug hunt 2026-11-05 #3). Kept with what's owed across
/// launches, so a relaunch knows it too (review of the fixes, E5): only
/// ParentLocker's mark id and the app's own note, never anyone else's words.
/// `comment` nil: the save left the Notes box as it was.
nonisolated struct ParentLockerSentRow: Codable, Sendable, Equatable {
    let markID: String?
    let comment: String?

    init(_ entry: ParentLockerPlanner.Entry) {
        markID = entry.attendance["attendance_code"]?["id"]?.nonEmptyID
        comment = entry.comment
    }

    /// Whether ParentLocker holds this save in `row`: the same saved mark,
    /// and the app's note as it was written.
    func landed(in row: ParentLockerSeen.Row) -> Bool {
        markID != nil && row.markID == markID && (comment == nil || row.comment == comment)
    }
}

/// Today's Close Arrival & Send runs taken and not yet ended, and whether
/// its Undo came since (`ParentLockerSync.closeArrivalSendUnderWay`, review
/// of the 2026-11-05 fixes, E1).
nonisolated struct ParentLockerCloseArrivalRuns: Sendable {
    /// By token: undone since it was taken.
    private var undone: [Int: Bool] = [:]
    private var last = 0
    /// The run of these sending now (`ParentLockerSync.perform`).
    var performing: Int?

    /// A run taken, from now until `end`.
    mutating func begin() -> Int {
        last += 1
        undone[last] = false
        return last
    }

    mutating func end(_ token: Int) {
        undone[token] = nil
        if performing == token { performing = nil }
    }

    /// Whether Close Arrival's Undo came since `token` was taken.
    func isUndone(_ token: Int?) -> Bool {
        token.map { undone[$0] == true } ?? false
    }

    /// A run taken that no Undo has stopped.
    var underWay: Bool { undone.values.contains(false) }

    /// Undo: every run taken stops before its next class.
    mutating func undoAll() {
        for token in undone.keys { undone[token] = true }
    }
}

/// What today's runs found that stands on the ParentLocker line until a run
/// shows it fixed (review of the 2026-11-05 fixes, E7, W2): each child left
/// alone for a reason someone must see (not matched, locked, a mark the
/// school's page lacks), and each class ParentLocker refused to open twice.
/// A run for some children replaces only those children's lines. One day's:
/// a new day, Leave Classroom and Sign Out start it afresh.
nonisolated struct ParentLockerStanding: Sendable, Equatable {
    /// Why the last run that compared each child left them alone, in the
    /// order the runs found them.
    var skips: [ParentLockerPlanner.Skip] = []
    /// Classes ParentLocker refused to open today: refused again, they stand.
    var refusedOnce: Set<Int> = []
    /// The classes standing refused, by `course_id`, with their names.
    var refused: [Int: String] = [:]
    /// The lines, as last written.
    var lines: [String] = []
}
