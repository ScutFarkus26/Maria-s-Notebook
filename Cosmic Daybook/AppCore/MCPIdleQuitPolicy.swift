//
//  MCPIdleQuitPolicy.swift
//  Cosmic Daybook
//
//  When an MCP-only launch may quit. The app was started for Claude, so it
//  stays while a Claude client is connected or one of its windows is open,
//  and quits once neither has been true for the whole idle interval. Pure —
//  no timers, no AppKit — so the rule is testable on any platform; the Mac
//  wiring is MCPIdleQuitController.
//

nonisolated struct MCPIdleQuitPolicy: Sendable {
    typealias Instant = ContinuousClock.Instant

    /// About ten minutes after the last Claude connection closes (Danny's
    /// decision, 2026-09-25).
    static let defaultIdleInterval: Duration = .seconds(10 * 60)

    let idleInterval: Duration
    private(set) var openConnections = 0
    private(set) var openWindows = 0
    /// When the app last became quiet — no Claude client connected and no
    /// window open. Nil while either is.
    private(set) var quietSince: Instant?

    /// An MCP-only launch starts quiet: its countdown runs from launch until
    /// the first Claude client connects.
    init(idleInterval: Duration = Self.defaultIdleInterval, launchedAt launch: Instant) {
        self.idleInterval = idleInterval
        quietSince = launch
    }

    var isQuiet: Bool { openConnections == 0 && openWindows == 0 }

    /// When the app quits if nothing else happens; nil while a client is
    /// connected or a window is open.
    var quitDeadline: Instant? { quietSince.map { $0.advanced(by: idleInterval) } }

    /// The number of connected Claude clients changed.
    mutating func connectionCountChanged(to count: Int, at now: Instant) {
        let wasQuiet = isQuiet
        openConnections = max(0, count)
        settle(wasQuiet: wasQuiet, at: now)
    }

    /// The number of open windows changed (or was merely recounted).
    mutating func windowCountChanged(to count: Int, at now: Instant) {
        let wasQuiet = isQuiet
        openWindows = max(0, count)
        settle(wasQuiet: wasQuiet, at: now)
    }

    /// True only once the app has been quiet for the whole idle interval.
    func shouldQuit(at now: Instant) -> Bool {
        guard let quitDeadline else { return false }
        return now >= quitDeadline
    }

    /// Anything open cancels the countdown; becoming quiet again starts a full
    /// new one. Staying quiet — a recount that found nothing new — leaves the
    /// countdown where it was, so spurious window notifications never
    /// postpone the quit.
    private mutating func settle(wasQuiet: Bool, at now: Instant) {
        if !isQuiet {
            quietSince = nil
        } else if !wasQuiet {
            quietSince = now
        }
    }
}
