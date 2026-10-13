import Foundation

// What `ParentLockerSync` runs: one run, for the whole class or some
// children, and a whole-class send owed until it can go.

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
    /// `.sendNow`: Send Now made while this device needed a sign-in.
    enum Reason: Sendable, Equatable { case closeArrival, backstop, owed, sendNow }
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

    /// A failed whole-class `job`, owed until it can go again: Close Arrival
    /// & Send's stays one, so its Undo can still take it back (bug hunt
    /// 2026-10-13 afternoon, H2); any other is a send owed.
    init(retrying job: ParentLockerJob) {
        self.init(reason: job.reason == .closeArrival ? .closeArrival : .owed, due: nil, attempt: 1)
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
