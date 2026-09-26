//
//  IdleMemoryTrimPolicy.swift
//  Cosmic Daybook
//
//  When the Mac app trims what it can rebuild because it has gone idle
//  rather than because the system asked. A Mac with plenty of RAM almost
//  never sends a memory-pressure event, so without this the album library's
//  covers, folded page text and query models stay resident for a multi-day
//  session. Pure — no timers, no AppKit — so the rule is testable on any
//  platform; the Mac wiring is IdleMemoryTrimController, and the trim itself
//  is AppDependencies.trimIdleMemory (which iOS calls on entering the
//  background).
//

/// Why an idle trim ran, for the log line.
nonisolated enum IdleMemoryTrimReason: String, Sendable {
    case appBackgrounded = "app moved to the background"
    case appInactive = "Mac app inactive"
    case lastMainWindowClosed = "last main window closed"
}

nonisolated struct IdleMemoryTrimPolicy: Sendable {
    typealias Instant = ContinuousClock.Instant

    /// About ten minutes of another app being frontmost.
    static let defaultInactiveInterval: Duration = .seconds(10 * 60)

    private enum Phase: Equatable, Sendable {
        case active
        case inactive(since: Instant)
        /// Still inactive, and this inactive spell's trim has run.
        case trimmed
    }

    let inactiveInterval: Duration
    private var phase: Phase = .active

    init(inactiveInterval: Duration = Self.defaultInactiveInterval) {
        self.inactiveInterval = inactiveInterval
    }

    /// When the trim runs if the app stays inactive; nil while it is active,
    /// and once this inactive spell's trim has run.
    var trimDeadline: Instant? {
        guard case .inactive(let since) = phase else { return nil }
        return since.advanced(by: inactiveInterval)
    }

    /// The app stopped being frontmost. A repeat while it is already inactive
    /// keeps the original start, so a spurious notification never postpones
    /// the trim, and never re-arms one that has already run.
    mutating func appResignedActive(at now: Instant) {
        guard phase == .active else { return }
        phase = .inactive(since: now)
    }

    /// The app is frontmost again. A pending trim is cancelled; the next time
    /// it resigns, a full new interval starts.
    mutating func appBecameActive() {
        phase = .active
    }

    /// The countdown woke. True — once per inactive spell — only when the app
    /// has stayed inactive for the whole interval. An early wake leaves the
    /// deadline where it is; a stale one (the app became active meanwhile)
    /// finds no deadline.
    mutating func countdownElapsed(at now: Instant) -> Bool {
        guard let trimDeadline, now >= trimDeadline else { return false }
        phase = .trimmed
        return true
    }

    /// A window is closing. True when it is a main window and no other main
    /// window is still open: the Albums section, the only place covers show,
    /// has gone with it.
    static func shouldTrimOnWindowClose(closingMainWindow: Bool, otherOpenMainWindows: Int) -> Bool {
        closingMainWindow && otherOpenMainWindows == 0
    }
}
